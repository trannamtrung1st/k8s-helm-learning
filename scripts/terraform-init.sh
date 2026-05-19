#!/bin/bash

# Provision Azure remote-state resources (if missing), then terraform init.
# Run from repository root:
#   ./scripts/terraform-init.sh
#   ./scripts/terraform-init.sh --skip-provision   # init only
#
# Requires: terraform, Azure CLI (az) logged in for provisioning
# -backend-config is only valid for `terraform init`, not `plan`.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"
VAR_FILE="${VAR_FILE:-vars/prod.tfvars}"

TF_STATE_RG="${TF_STATE_RG:-workbench-tf}"
TF_STATE_STORAGE_ACCOUNT="${TF_STATE_STORAGE_ACCOUNT:-workbenchstorage77}"
TF_STATE_CONTAINER="${TF_STATE_CONTAINER:-workbench-tf}"
TF_STATE_KEY="${TF_STATE_KEY:-terraform.tfstate}"
TF_STATE_LOCATION="${TF_STATE_LOCATION:-southeastasia}"

SKIP_PROVISION="${SKIP_TF_BACKEND_PROVISION:-false}"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

_tfvar() {
  local key="$1"
  grep -E "^[[:space:]]*${key}[[:space:]]*=" "${TF_DIR}/${VAR_FILE}" 2>/dev/null \
    | head -1 \
    | cut -d= -f2- \
    | tr -d ' "'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-provision)
      SKIP_PROVISION=true
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

TENANT_ID="${TENANT_ID:-$(_tfvar tenant_id)}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(_tfvar subscription_id)}"

# Optional: align state RG region with main_rg_location when set in tfvars (Azure CLI slug)
_main_location="$(_tfvar main_rg_location)"
if [[ -n "${_main_location}" ]]; then
  case "${_main_location}" in
    "South East Asia"|"Southeast Asia") TF_STATE_LOCATION=southeastasia ;;
    *)
      # Use tfvars value as-is if it is already an Azure region slug (e.g. southeastasia)
      TF_STATE_LOCATION="${_main_location}"
      ;;
  esac
fi

provision_tf_backend() {
  if ! command -v az >/dev/null 2>&1; then
    echo "Azure CLI (az) is required to provision the remote state backend." >&2
    echo "Install az or run: SKIP_TF_BACKEND_PROVISION=1 ./scripts/terraform-init.sh --skip-provision" >&2
    exit 1
  fi

  if [[ -z "${SUBSCRIPTION_ID}" ]]; then
    echo "subscription_id not set. Add it to ${TF_DIR}/${VAR_FILE} or export SUBSCRIPTION_ID." >&2
    exit 1
  fi

  echo "==> Provisioning Terraform remote state (subscription: ${SUBSCRIPTION_ID})"
  az account set --subscription "${SUBSCRIPTION_ID}"

  if az group show --name "${TF_STATE_RG}" >/dev/null 2>&1; then
    echo "    Resource group ${TF_STATE_RG} already exists"
  else
    echo "    Creating resource group ${TF_STATE_RG} (${TF_STATE_LOCATION})"
    az group create \
      --name "${TF_STATE_RG}" \
      --location "${TF_STATE_LOCATION}" \
      --output none
  fi

  if az storage account show --name "${TF_STATE_STORAGE_ACCOUNT}" --resource-group "${TF_STATE_RG}" >/dev/null 2>&1; then
    echo "    Storage account ${TF_STATE_STORAGE_ACCOUNT} already exists"
  else
    echo "    Creating storage account ${TF_STATE_STORAGE_ACCOUNT}"
    az storage account create \
      --name "${TF_STATE_STORAGE_ACCOUNT}" \
      --resource-group "${TF_STATE_RG}" \
      --location "${TF_STATE_LOCATION}" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --min-tls-version TLS1_2 \
      --allow-blob-public-access false \
      --allow-shared-key-access false \
      --output none
  fi

  if az storage container exists \
    --name "${TF_STATE_CONTAINER}" \
    --account-name "${TF_STATE_STORAGE_ACCOUNT}" \
    --auth-mode login \
    --output tsv 2>/dev/null | grep -q true; then
    echo "    Container ${TF_STATE_CONTAINER} already exists"
  else
    echo "    Creating blob container ${TF_STATE_CONTAINER}"
    az storage container create \
      --name "${TF_STATE_CONTAINER}" \
      --account-name "${TF_STATE_STORAGE_ACCOUNT}" \
      --auth-mode login \
      --output none
  fi

  echo "==> Remote state backend ready:"
  echo "    resource_group      = ${TF_STATE_RG}"
  echo "    storage_account     = ${TF_STATE_STORAGE_ACCOUNT}"
  echo "    container           = ${TF_STATE_CONTAINER}"
  echo "    state_key           = ${TF_STATE_KEY}"
}

if [[ "${SKIP_PROVISION}" != "true" ]]; then
  provision_tf_backend
else
  echo "==> Skipping backend provisioning (SKIP_TF_BACKEND_PROVISION / --skip-provision)"
fi

if [[ -z "${TENANT_ID}" ]]; then
  echo "tenant_id not set. Add it to ${TF_DIR}/${VAR_FILE} or export TENANT_ID." >&2
  exit 1
fi

echo "==> terraform init"
terraform -chdir="${TF_DIR}" init \
  -backend-config="resource_group_name=${TF_STATE_RG}" \
  -backend-config="storage_account_name=${TF_STATE_STORAGE_ACCOUNT}" \
  -backend-config="container_name=${TF_STATE_CONTAINER}" \
  -backend-config="key=${TF_STATE_KEY}" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="use_oidc=${TF_BACKEND_USE_OIDC:-true}" \
  -backend-config="tenant_id=${TENANT_ID}"
