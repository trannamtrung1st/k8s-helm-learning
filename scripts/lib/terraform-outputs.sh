#!/bin/bash
# shellcheck shell=bash
# Read Workbench Terraform outputs into the environment.
#
# Usage (from repo root):
#   ROOT="$(cd .../.. && pwd)"
#   # shellcheck source=scripts/lib/terraform-outputs.sh
#   source "${ROOT}/scripts/lib/terraform-outputs.sh"
#   terraform_outputs_load
#   terraform_outputs_apply_env
#
# Exports when outputs exist (env vars already set take precedence):
#   KEY_VAULT_NAME (from key_vault_name output)

terraform_outputs_load() {
  local tf_dir="${ROOT}/devops/terraform"

  TF_OUT_KEY_VAULT_NAME=""

  if ! command -v terraform >/dev/null 2>&1; then
    return 1
  fi
  if [[ ! -d "${tf_dir}/.terraform" ]]; then
    return 1
  fi

  _tf_out() {
    terraform -chdir="${tf_dir}" output -raw "$1" 2>/dev/null || true
  }

  TF_OUT_KEY_VAULT_NAME="$(_tf_out key_vault_name)"

  [[ -n "${TF_OUT_KEY_VAULT_NAME}" ]]
}

terraform_outputs_apply_env() {
  terraform_outputs_load || true

  if [[ -n "${TF_OUT_KEY_VAULT_NAME}" ]]; then
    : "${KEY_VAULT_NAME:=${TF_OUT_KEY_VAULT_NAME}}"
  fi

  export KEY_VAULT_NAME
}
