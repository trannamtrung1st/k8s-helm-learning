#!/bin/bash
set -euo pipefail

# Plan Terraform from the repository root:
#   ./scripts/terraform-init.sh
#   ./scripts/terraform-plan.sh
#   ./scripts/terraform-apply.sh
#   ./scripts/terraform-destroy.sh
#
# Options:
#   --target <resource>   Limit plan to resource (repeatable)
#   -h, --help            Show help
#
# Environment:
#   VAR_FILE=vars/prod.tfvars
#   SECRETS_VAR_FILE=vars/secrets.tfvars   (auto-included when the file exists)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"
# shellcheck source=scripts/lib/terraform-varfiles.sh
source "${ROOT}/scripts/lib/terraform-varfiles.sh"

TARGETS=()

usage() {
  cat <<'EOF'
Run terraform plan from the repository root.

Usage:
  ./scripts/terraform-plan.sh [options]

Options:
  --target <resource>   Limit plan to resource (repeatable)
  -h, --help            Show this help

Environment:
  VAR_FILE              Primary var file under devops/terraform/ (default: vars/prod.tfvars)
  SECRETS_VAR_FILE      Secrets var file (default: vars/secrets.tfvars)
  USE_SECRETS_TFVARS    auto | true | false — see scripts/lib/terraform-varfiles.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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

terraform_varfiles_build "${TF_DIR}"

cmd=(terraform -chdir="${TF_DIR}" plan "${TERRAFORM_VARFILES[@]}")
if ((${#TARGETS[@]})); then
  for t in "${TARGETS[@]}"; do
    cmd+=( -target="${t}" )
  done
fi

echo "==> terraform plan -var-file=$(terraform_varfiles_label "${TF_DIR}")"
exec "${cmd[@]}"
