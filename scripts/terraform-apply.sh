#!/bin/bash
set -euo pipefail

# Apply Terraform from the repository root:
#   ./scripts/terraform-init.sh
#   ./scripts/terraform-plan.sh
#   ./scripts/terraform-apply.sh
#
# Options:
#   --auto-approve, -y     Apply without interactive approval
#   --plan-first           Run plan before apply (prompts unless -y)
#   --destroy              Same as ./scripts/terraform-destroy.sh (prefer that script)
#   --refresh-only         Run terraform apply -refresh-only
#   --target <resource>    Limit to resource (repeatable)
#   --replace <resource>   Replace resource (repeatable; apply/destroy only)
#
# Environment:
#   VAR_FILE=vars/prod.tfvars
#   SECRETS_VAR_FILE=vars/secrets.tfvars   (auto-included when the file exists)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"
# shellcheck source=scripts/lib/terraform-varfiles.sh
source "${ROOT}/scripts/lib/terraform-varfiles.sh"

AUTO_APPROVE=false
PLAN_FIRST=false
DESTROY=false
REFRESH_ONLY=false
TARGETS=()
REPLACES=()

usage() {
  cat <<'EOF'
Apply (or destroy) Terraform from the repository root.

Usage:
  ./scripts/terraform-apply.sh [options]

Options:
  -y, --auto-approve     Skip Terraform's approval prompt (and plan-first prompt)
  --plan-first           Run terraform plan before apply; confirm unless -y
  --destroy              Run terraform destroy instead of apply
  --refresh-only         Run terraform apply -refresh-only
  --target <resource>    Limit change to resource (repeatable)
  --replace <resource>   Force replace resource on apply (repeatable)
  -h, --help             Show this help

Environment:
  VAR_FILE               Primary var file under devops/terraform/ (default: vars/prod.tfvars)
  SECRETS_VAR_FILE       Secrets var file (default: vars/secrets.tfvars)
  USE_SECRETS_TFVARS     auto | true | false — see scripts/lib/terraform-varfiles.sh

Examples:
  ./scripts/terraform-apply.sh --plan-first
  ./scripts/terraform-apply.sh -y
  ./scripts/terraform-apply.sh --target=azurerm_resource_group.workbench
  ./scripts/terraform-destroy.sh --plan-first   # preferred for destroy
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
    --destroy)
      DESTROY=true
      shift
      ;;
    --refresh-only)
      REFRESH_ONLY=true
      shift
      ;;
    --target)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --target" >&2
        exit 1
      fi
      TARGETS+=("$2")
      shift 2
      ;;
    --target=*)
      TARGETS+=("${1#--target=}")
      shift
      ;;
    --replace)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --replace" >&2
        exit 1
      fi
      REPLACES+=("$2")
      shift 2
      ;;
    --replace=*)
      REPLACES+=("${1#--replace=}")
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

if [[ "${REFRESH_ONLY}" == "true" && "${DESTROY}" == "true" ]]; then
  echo "Cannot use --refresh-only with --destroy." >&2
  exit 1
fi

if [[ "${REFRESH_ONLY}" == "true" && ${#REPLACES[@]:-0} -gt 0 ]]; then
  echo "Cannot use --replace with --refresh-only." >&2
  exit 1
fi

terraform_varfiles_build "${TF_DIR}"
VARFILES_LABEL="$(terraform_varfiles_label "${TF_DIR}")"

plan_cmd=(terraform -chdir="${TF_DIR}" plan "${TERRAFORM_VARFILES[@]}")
apply_cmd=()
if [[ "${DESTROY}" == "true" ]]; then
  apply_cmd=(terraform -chdir="${TF_DIR}" destroy "${TERRAFORM_VARFILES[@]}")
else
  apply_cmd=(terraform -chdir="${TF_DIR}" apply "${TERRAFORM_VARFILES[@]}")
  if [[ "${REFRESH_ONLY}" == "true" ]]; then
    apply_cmd+=( -refresh-only )
  fi
fi

if ((${#TARGETS[@]})); then
  for t in "${TARGETS[@]}"; do
    plan_cmd+=( -target="${t}" )
    apply_cmd+=( -target="${t}" )
  done
fi

if [[ "${DESTROY}" != "true" ]] && ((${#REPLACES[@]})); then
  for r in "${REPLACES[@]}"; do
    apply_cmd+=( -replace="${r}" )
  done
fi

if [[ "${AUTO_APPROVE}" == "true" ]]; then
  apply_cmd+=( -auto-approve )
fi

run_plan_first() {
  echo "==> terraform plan -var-file=${VARFILES_LABEL}"
  "${plan_cmd[@]}"
}

confirm_apply() {
  local action="apply"
  [[ "${DESTROY}" == "true" ]] && action="destroy"
  read -r -p "Proceed with terraform ${action}? [y/N] " reply
  reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

if [[ "${PLAN_FIRST}" == "true" ]]; then
  run_plan_first
  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    if ! confirm_apply; then
      echo "Aborted."
      exit 0
    fi
    apply_cmd+=( -auto-approve )
  fi
fi

action_label="apply"
[[ "${DESTROY}" == "true" ]] && action_label="destroy"
[[ "${REFRESH_ONLY}" == "true" ]] && action_label="apply (refresh-only)"

echo "==> terraform ${action_label} -var-file=${VARFILES_LABEL}"
exec "${apply_cmd[@]}"
