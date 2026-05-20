#!/bin/bash
set -euo pipefail

# End-to-end first-run setup for Workbench on AKS (counterpart to kind-e2e-first-run.sh).
# Run from repository root.
#
# Prerequisites:
#   - az login
#   - devops/terraform/vars/prod.tfvars (and vars/secrets.tfvars for Key Vault secrets)
#   - Key Vault Secrets User on workbench-kv for helm apply (after Terraform)
#
# Flow:
#   1) terraform init (remote backend + providers)
#   2) terraform apply (AKS, ACR, Key Vault, …)
#   3) fetch AKS kubeconfig and set kubectl context
#   4) verify cluster nodes
#   5) build app images (linux/amd64) via Docker Compose
#   6) push app images to ACR
#   7) helm apply --cluster aks (Key Vault credential overlay)
#   8) verify namespaces and pods
#
# Unlike kind-e2e-first-run.sh, this script does NOT:
#   - create kind, label infra nodes, init hostPath volumes, or load images into kind
#   AKS uses managed-csi PVCs and pulls app images from ACR (AcrPull via Terraform).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${COMPOSE_FILE:-${ROOT}/local/docker-compose.yaml}"
HELM_CLUSTER="aks"
INCLUDE_JOBS="${INCLUDE_JOBS:-1}"
TF_DIR="${ROOT}/devops/terraform"
VAR_FILE="${VAR_FILE:-vars/prod.tfvars}"

AKS_RESOURCE_GROUP="${AKS_RESOURCE_GROUP:-}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-}"
ACR_NAME="${ACR_NAME:-workbenchacr77}"

SKIP_TERRAFORM="false"
SKIP_TERRAFORM_INIT="false"
TF_PLAN_FIRST="true"
TF_AUTO_APPROVE="false"
SKIP_CREDENTIALS="false"
SKIP_BUILD="false"
SKIP_PUSH="false"
SKIP_APPLY="false"
SKIP_KV_SECRETS="false"
ATTACH_ACR="false"

usage() {
  cat <<EOF
Usage: $0 [options]

End-to-end AKS bring-up: Terraform → kubeconfig → build → push to ACR → helm apply.

Options:
  Terraform:
    --skip-terraform           Skip terraform init and apply (cluster already provisioned)
    --skip-terraform-init      Skip terraform init only
    --no-terraform-plan-first  Apply without running plan first
    -y, --auto-approve         Auto-approve terraform apply (and plan-first confirm)

  Azure / AKS:
    --resource-group <name>    AKS resource group (default: devops/clusters/aks/cluster.conf)
    --aks-name <name>          AKS cluster name (default: workbench-aks)
    --acr-name <name>          ACR name (default: workbenchacr77)
    --skip-credentials         Do not run az aks get-credentials
    --attach-acr               Run az aks update --attach-acr

  Images / Helm:
    --skip-build               Skip docker compose build
    --skip-push                Skip docker compose push to ACR
    --skip-apply               Skip helm apply
    --skip-kv-secrets          Pass --skip-kv-secrets to helm-apply
    --no-jobs                  Omit workbench-jobs from compose build/push

  -h, --help                   Show this help

Environment:
  VAR_FILE, SECRETS_VAR_FILE, USE_SECRETS_TFVARS  (see scripts/lib/terraform-varfiles.sh)
  COMPOSE_FILE, INCLUDE_JOBS, AKS_RESOURCE_GROUP, AKS_CLUSTER_NAME, ACR_NAME

Examples:
  $0
  $0 -y
  $0 --skip-terraform --skip-build --skip-push
  $0 --resource-group workbench --aks-name workbench-aks

See also: ./scripts/kind-e2e-first-run.sh (local kind flow)
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

load_aks_defaults() {
  local conf="${ROOT}/devops/clusters/aks/cluster.conf"
  if [[ -f "${conf}" ]]; then
    # shellcheck disable=SC1090
    source "${conf}"
  fi
  : "${AKS_RESOURCE_GROUP:=workbench}"
  : "${AKS_CLUSTER_NAME:=workbench-aks}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-terraform)
      SKIP_TERRAFORM="true"
      shift
      ;;
    --skip-terraform-init)
      SKIP_TERRAFORM_INIT="true"
      shift
      ;;
    --no-terraform-plan-first)
      TF_PLAN_FIRST="false"
      shift
      ;;
    -y|--auto-approve)
      TF_AUTO_APPROVE="true"
      shift
      ;;
    --resource-group)
      [[ $# -ge 2 ]] || { echo "Missing value for --resource-group" >&2; exit 1; }
      AKS_RESOURCE_GROUP="$2"
      shift 2
      ;;
    --aks-name)
      [[ $# -ge 2 ]] || { echo "Missing value for --aks-name" >&2; exit 1; }
      AKS_CLUSTER_NAME="$2"
      shift 2
      ;;
    --acr-name)
      [[ $# -ge 2 ]] || { echo "Missing value for --acr-name" >&2; exit 1; }
      ACR_NAME="$2"
      shift 2
      ;;
    --skip-credentials)
      SKIP_CREDENTIALS="true"
      shift
      ;;
    --skip-build)
      SKIP_BUILD="true"
      shift
      ;;
    --skip-push)
      SKIP_PUSH="true"
      shift
      ;;
    --skip-apply)
      SKIP_APPLY="true"
      shift
      ;;
    --skip-kv-secrets)
      SKIP_KV_SECRETS="true"
      shift
      ;;
    --no-jobs)
      INCLUDE_JOBS=0
      shift
      ;;
    --attach-acr)
      ATTACH_ACR="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -f "${ROOT}/devops/clusters/aks/global-values.yaml" ]]; then
  echo "Run this script from repository root (missing devops/clusters/aks/global-values.yaml)." >&2
  exit 1
fi

load_aks_defaults

require_cmd az
require_cmd kubectl
require_cmd docker
if [[ "${SKIP_TERRAFORM}" != "true" ]]; then
  require_cmd terraform
fi
if [[ "${SKIP_APPLY}" != "true" ]]; then
  require_cmd helm
fi
if [[ "${SKIP_BUILD}" != "true" || "${SKIP_PUSH}" != "true" ]]; then
  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose v2 ('docker compose') is required." >&2
    exit 1
  fi
fi
if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Compose file not found: ${COMPOSE_FILE}" >&2
  exit 1
fi

if [[ "${SKIP_TERRAFORM}" != "true" ]]; then
  if [[ ! -f "${TF_DIR}/${VAR_FILE}" ]]; then
    echo "Missing Terraform var file: ${TF_DIR}/${VAR_FILE}" >&2
    echo "Copy devops/terraform/vars/prod.tfvars.example and configure (see devops/terraform/README.md)." >&2
    exit 1
  fi

  if [[ "${SKIP_TERRAFORM_INIT}" != "true" ]]; then
    echo "=== Step 1: terraform init ==="
    ./scripts/terraform-init.sh
  else
    echo "=== Step 1: skip terraform init ==="
  fi

  echo "=== Step 2: terraform apply ==="
  tf_apply_args=()
  if [[ "${TF_AUTO_APPROVE}" == "true" ]]; then
    tf_apply_args+=(-y)
  fi
  if [[ "${TF_PLAN_FIRST}" == "true" ]]; then
    tf_apply_args+=(--plan-first)
  fi
  ./scripts/terraform-apply.sh "${tf_apply_args[@]}"
else
  echo "=== Steps 1–2: skip terraform (init + apply) ==="
fi

echo "=== Step 3: AKS kubeconfig and kubectl context ==="
echo "Target: resource group=${AKS_RESOURCE_GROUP}, cluster=${AKS_CLUSTER_NAME}"
if [[ "${SKIP_CREDENTIALS}" != "true" ]]; then
  echo "==> az aks get-credentials --resource-group ${AKS_RESOURCE_GROUP} --name ${AKS_CLUSTER_NAME}"
  az aks get-credentials \
    --resource-group "${AKS_RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing
fi
# shellcheck source=scripts/lib/helm-kubectl-context.sh
source "${ROOT}/scripts/lib/helm-kubectl-context.sh"
export HELM_FETCH_AKS_CREDENTIALS=false
helm_kubectl_use_context "${HELM_CLUSTER}"

echo "=== Step 4: verify cluster ==="
kubectl get nodes -o wide
if [[ "${ATTACH_ACR}" == "true" ]]; then
  echo "=== Step 4b: attach ACR to AKS (optional) ==="
  echo "==> az aks update --resource-group ${AKS_RESOURCE_GROUP} --name ${AKS_CLUSTER_NAME} --attach-acr ${ACR_NAME}"
  az aks update \
    --resource-group "${AKS_RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --attach-acr "${ACR_NAME}"
else
  echo "Step 4b: skip ACR attach (Terraform AcrPull role is the default path; pass --attach-acr to run az aks update)"
fi

if [[ "${SKIP_BUILD}" != "true" ]]; then
  echo "=== Step 5: build app images (linux/amd64) ==="
  export INCLUDE_JOBS
  ./scripts/compose-wizard.sh build
else
  echo "=== Step 5: skip build ==="
fi

if [[ "${SKIP_PUSH}" != "true" ]]; then
  echo "=== Step 6: push app images to ACR ==="
  export INCLUDE_JOBS
  ./scripts/compose-wizard.sh push
else
  echo "=== Step 6: skip push ==="
fi

if [[ "${SKIP_APPLY}" != "true" ]]; then
  echo "=== Step 7: apply stack (Helm, cluster=aks) ==="
  helm_apply_args=(--cluster aks)
  if [[ "${SKIP_KV_SECRETS}" == "true" ]]; then
    helm_apply_args+=(--skip-kv-secrets)
  fi
  ./scripts/helm-apply.sh "${helm_apply_args[@]}"
else
  echo "=== Step 7: skip apply ==="
fi

echo "=== Step 8: verify ==="
kubectl get ns
kubectl get pods -n workbench-db
kubectl get pods -n workbench-infra
kubectl get pods -n workbench-apps
kubectl get svc -n workbench-infra
kubectl get svc -n workbench-apps

echo "Done."
