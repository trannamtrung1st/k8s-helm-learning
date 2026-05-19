#!/bin/bash
set -euo pipefail

# Destroy Terraform-managed resources from the repository root:
#   ./scripts/terraform-init.sh
#   ./scripts/terraform-destroy.sh --plan-first
#
# Options:
#   -y, --auto-approve     Destroy without interactive approval
#   --plan-first           Run terraform plan -destroy first (prompts unless -y)
#   --target <resource>    Limit destroy to resource (repeatable)
#
# Environment:
#   VAR_FILE=vars/prod.tfvars   Var file under devops/terraform/ (default)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"
VAR_FILE="${VAR_FILE:-vars/prod.tfvars}"

AUTO_APPROVE=false
PLAN_FIRST=false
TARGETS=()

usage() {
  cat <<'EOF'
Destroy Terraform-managed resources from the repository root.

Usage:
  ./scripts/terraform-destroy.sh [options]

Options:
  -y, --auto-approve     Skip Terraform's destroy confirmation (and plan-first prompt)
  --plan-first           Run terraform plan -destroy before destroy; confirm unless -y
  --target <resource>    Destroy only this resource (repeatable)
  -h, --help             Show this help

Environment:
  VAR_FILE               Var file path relative to devops/terraform/
                         (default: vars/prod.tfvars)

Examples:
  ./scripts/terraform-destroy.sh --plan-first
  ./scripts/terraform-destroy.sh -y
  ./scripts/terraform-destroy.sh --target=azurerm_resource_group.workbench --plan-first
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--auto-approve)
      AUTO_APPROVE=true
      shift
      ;;
    --plan-first)
      PLAN_FIRST=true
      shift
      ;;
    --target)
      [[ $# -ge 2 ]] || { echo "Missing value for --target" >&2; exit 1; }
      TARGETS+=("$2")
      shift 2
      ;;
    --target=*)
      TARGETS+=("${1#--target=}")
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

plan_cmd=(terraform -chdir="${TF_DIR}" plan -destroy -var-file="${VAR_FILE}")
destroy_cmd=(terraform -chdir="${TF_DIR}" destroy -var-file="${VAR_FILE}")

if ((${#TARGETS[@]})); then
  for t in "${TARGETS[@]}"; do
    plan_cmd+=( -target="${t}" )
    destroy_cmd+=( -target="${t}" )
  done
fi

if [[ "${AUTO_APPROVE}" == "true" ]]; then
  destroy_cmd+=( -auto-approve )
fi

confirm_destroy() {
  read -r -p "Proceed with terraform destroy? [y/N] " reply
  reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

if [[ "${PLAN_FIRST}" == "true" ]]; then
  echo "==> terraform plan -destroy -var-file=${VAR_FILE}"
  "${plan_cmd[@]}"
  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    if ! confirm_destroy; then
      echo "Aborted."
      exit 0
    fi
    destroy_cmd+=( -auto-approve )
  fi
fi

echo "==> terraform destroy -var-file=${VAR_FILE}"
exec "${destroy_cmd[@]}"
