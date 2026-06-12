#!/bin/bash
set -euo pipefail

# Quick end-to-end first-run setup for local kind cluster.
# Run from repository root.
#
# Mirrors devops/k8s/README.md first-run flow:
# 1) create/recreate kind cluster
# 2) set kubectl context
# 2b) install Istio ambient + Gateway API CRDs (Helm; see scripts/istio-helm-install.sh)
# 2c) install RabbitMQ Cluster Operator (see scripts/rabbitmq-install.sh)
# 2d) install cert-manager (see scripts/cert-manager-install.sh)
# 3) label infra node
# 4) init local PV directories
# 5) build compose app images and load into kind
# 6) apply stack (Helm by default; --k8s for legacy Kustomize)

CLUSTER_NAME="workbench-0"
WORKERS="2"
RECREATE="false"
INFRA_NODE=""
SKIP_BUILD="false"
SKIP_LOAD="false"
SKIP_APPLY="false"
SKIP_ISTIO="false"
SKIP_RABBITMQ="false"
SKIP_CERT_MANAGER="false"
USE_K8S_APPLY="false"
COMPOSE_FILE="local/docker-compose.yaml"
INCLUDE_JOBS="${INCLUDE_JOBS:-1}"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --cluster <name>       kind cluster name (default: ${CLUSTER_NAME})
  --workers <n>          kind worker count (default: ${WORKERS})
  --recreate             delete existing cluster with same name first
  --infra-node <name>    node to label as workbench.io/infra-node=true
                         (default: first worker if present, else control-plane)
  --skip-build           skip app image build step (compose-wizard build)
  --skip-load            skip kind image load step
  --no-jobs              omit workbench-jobs from build and kind load
  --skip-apply           skip stack apply step (Helm or Kustomize)
  --skip-istio           skip Istio ambient Helm install (+ Gateway API CRDs)
  --skip-rabbitmq        skip RabbitMQ Cluster Operator install
  --skip-cert-manager    skip cert-manager install
  --k8s                  apply with ./scripts/k8s-apply.sh (legacy Kustomize)
                         default: ./scripts/helm-apply.sh
  -h, --help             show help

Examples:
  $0
  $0 --cluster workbench-0 --workers 1 --recreate
  $0 --infra-node workbench-0-worker --skip-build
  $0 --k8s
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}"
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      CLUSTER_NAME="${2:-}"
      shift 2
      ;;
    --workers)
      WORKERS="${2:-}"
      shift 2
      ;;
    --recreate)
      RECREATE="true"
      shift
      ;;
    --infra-node)
      INFRA_NODE="${2:-}"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD="true"
      shift
      ;;
    --no-jobs)
      INCLUDE_JOBS=0
      shift
      ;;
    --skip-load)
      SKIP_LOAD="true"
      shift
      ;;
    --skip-apply)
      SKIP_APPLY="true"
      shift
      ;;
    --skip-istio)
      SKIP_ISTIO="true"
      shift
      ;;
    --skip-rabbitmq)
      SKIP_RABBITMQ="true"
      shift
      ;;
    --skip-cert-manager)
      SKIP_CERT_MANAGER="true"
      shift
      ;;
    --k8s)
      USE_K8S_APPLY="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ ! "${WORKERS}" =~ ^[0-9]+$ ]]; then
  echo "--workers must be a non-negative integer."
  exit 1
fi

if [[ ! -f "devops/k8s/README.md" ]]; then
  echo "Run this script from repository root."
  exit 1
fi

require_cmd kind
require_cmd kubectl
require_cmd docker
if [[ "${SKIP_ISTIO}" != "true" || "${SKIP_CERT_MANAGER}" != "true" || ( "${USE_K8S_APPLY}" != "true" && "${SKIP_APPLY}" != "true" ) ]]; then
  require_cmd helm
fi

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${COMPOSE_FILE}"
  exit 1
fi

echo "=== Step 1: create kind cluster ==="
if [[ "${RECREATE}" == "true" ]]; then
  ./scripts/kind-wizard.sh recreate --name "${CLUSTER_NAME}" --workers "${WORKERS}"
else
  if kind get clusters | awk '{print $1}' | grep -qx "${CLUSTER_NAME}"; then
    echo "Cluster '${CLUSTER_NAME}' already exists (skip create)."
  else
    ./scripts/kind-wizard.sh create --name "${CLUSTER_NAME}" --workers "${WORKERS}"
  fi
fi

echo "=== Step 2: set kubectl context ==="
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
kubectl get nodes -o wide

if [[ "${SKIP_ISTIO}" != "true" ]]; then
  echo "=== Step 2b: install Istio ambient (Helm) + Gateway API CRDs ==="
  ./scripts/istio-helm-install.sh
else
  echo "=== Step 2b: skip Istio Helm install ==="
fi

if [[ "${SKIP_RABBITMQ}" != "true" ]]; then
  echo "=== Step 2c: install RabbitMQ Cluster Operator ==="
  ./scripts/rabbitmq-install.sh
else
  echo "=== Step 2c: skip RabbitMQ operator install ==="
fi

if [[ "${SKIP_CERT_MANAGER}" != "true" ]]; then
  echo "=== Step 2d: install cert-manager ==="
  ./scripts/cert-manager-install.sh
else
  echo "=== Step 2d: skip cert-manager install ==="
fi

if [[ -z "${INFRA_NODE}" ]]; then
  # Prefer first worker in multi-node cluster; else control-plane in single-node.
  if kubectl get node "${CLUSTER_NAME}-worker" >/dev/null 2>&1; then
    INFRA_NODE="${CLUSTER_NAME}-worker"
  else
    INFRA_NODE="${CLUSTER_NAME}-control-plane"
  fi
fi

echo "=== Step 3: label infra node ==="
echo "Infra node: ${INFRA_NODE}"
./scripts/k8s-node-label-wizard.sh label --node "${INFRA_NODE}" workbench.io/infra-node=true

echo "=== Step 4: initialize volume directories ==="
./scripts/k8s-volumes-init.sh

if [[ "${SKIP_BUILD}" != "true" ]]; then
  echo "=== Step 5a: build app images (buildx multi-arch, load host arch) ==="
  export INCLUDE_JOBS
  ./scripts/compose-wizard.sh build
else
  echo "=== Step 5a: skip build ==="
fi

if [[ "${SKIP_LOAD}" != "true" ]]; then
  echo "=== Step 5b: load app images into kind ==="
  export INCLUDE_JOBS
  ./scripts/kind-load-images.sh --cluster "${CLUSTER_NAME}"
else
  echo "=== Step 5b: skip load ==="
fi

if [[ "${SKIP_APPLY}" != "true" ]]; then
  if [[ "${USE_K8S_APPLY}" == "true" ]]; then
    echo "=== Step 6: apply stack (Kustomize) ==="
    ./scripts/k8s-apply.sh
  else
    echo "=== Step 6: apply stack (Helm) ==="
    ./scripts/helm-apply.sh
  fi
else
  echo "=== Step 6: skip apply ==="
fi

echo "=== Verify ==="
if [[ "${SKIP_RABBITMQ}" != "true" ]]; then
  kubectl get crd rabbitmqclusters.rabbitmq.com
  kubectl get pods -n rabbitmq-system
fi
kubectl get ns
kubectl get pods -n workbench-db
kubectl get pods -n workbench-infra
if [[ "${SKIP_RABBITMQ}" != "true" && "${SKIP_APPLY}" != "true" ]]; then
  kubectl get rabbitmqclusters -n workbench-infra
fi
kubectl get pods -n workbench-apps
kubectl get svc -n workbench-infra
kubectl get svc -n workbench-apps
if [[ "${SKIP_ISTIO}" != "true" ]]; then
  kubectl get pods -n istio-system
fi
if [[ "${SKIP_CERT_MANAGER}" != "true" ]]; then
  kubectl get crd certificates.cert-manager.io
  kubectl get pods -n cert-manager
fi

echo "Done."
