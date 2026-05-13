#!/bin/bash
set -euo pipefail

# Quick end-to-end first-run setup for local kind cluster.
# Run from repository root.
#
# Mirrors devops/k8s/README.md first-run flow:
# 1) create/recreate kind cluster
# 2) set kubectl context
# 3) label infra node
# 4) init local PV directories
# 5) build compose app images and load into kind
# 6) apply kustomize stack

CLUSTER_NAME="workbench-0"
WORKERS="2"
RECREATE="false"
INFRA_NODE=""
SKIP_BUILD="false"
SKIP_LOAD="false"
SKIP_APPLY="false"
COMPOSE_FILE="local/docker-compose.yaml"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --cluster <name>       kind cluster name (default: ${CLUSTER_NAME})
  --workers <n>          kind worker count (default: ${WORKERS})
  --recreate             delete existing cluster with same name first
  --infra-node <name>    node to label as workbench.io/infra-node=true
                         (default: first worker if present, else control-plane)
  --skip-build           skip docker compose build step
  --skip-load            skip kind image load step
  --skip-apply           skip kubectl apply step
  -h, --help             show help

Examples:
  $0
  $0 --cluster workbench-0 --workers 1 --recreate
  $0 --infra-node workbench-0-worker --skip-build
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
    --skip-load)
      SKIP_LOAD="true"
      shift
      ;;
    --skip-apply)
      SKIP_APPLY="true"
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

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${COMPOSE_FILE}"
  exit 1
fi

echo "=== Step 1: create kind cluster ==="
if [[ "${RECREATE}" == "true" ]]; then
  ./scripts/kind-wizard.sh recreate --name "${CLUSTER_NAME}" --workers "${WORKERS}"
else
  if kind get clusters | awk '{print $1}' | rg -x "${CLUSTER_NAME}" >/dev/null 2>&1; then
    echo "Cluster '${CLUSTER_NAME}' already exists (skip create)."
  else
    ./scripts/kind-wizard.sh create --name "${CLUSTER_NAME}" --workers "${WORKERS}"
  fi
fi

echo "=== Step 2: set kubectl context ==="
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
kubectl get nodes -o wide

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
  echo "=== Step 5a: build compose images ==="
  docker compose -f "${COMPOSE_FILE}" build
else
  echo "=== Step 5a: skip build ==="
fi

if [[ "${SKIP_LOAD}" != "true" ]]; then
  echo "=== Step 5b: load compose images into kind ==="
  IMAGES=()
  while IFS= read -r image; do
    [[ -z "${image}" ]] && continue
    case "${image}" in
      workbench/*) IMAGES+=("${image}") ;;
    esac
  done < <(docker compose -f "${COMPOSE_FILE}" config --images)
  if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "No workbench images found in compose config."
    exit 1
  fi
  ./scripts/kind-load-images.sh --cluster "${CLUSTER_NAME}" "${IMAGES[@]}"
else
  echo "=== Step 5b: skip load ==="
fi

if [[ "${SKIP_APPLY}" != "true" ]]; then
  echo "=== Step 6: apply stack ==="
  ./scripts/k8s-apply.sh
else
  echo "=== Step 6: skip apply ==="
fi

echo "=== Verify ==="
kubectl get ns
kubectl get pods -n workbench-db
kubectl get pods -n workbench-infra
kubectl get pods -n workbench-system
kubectl get svc -n workbench-infra
kubectl get svc -n workbench-system

echo "Done."
