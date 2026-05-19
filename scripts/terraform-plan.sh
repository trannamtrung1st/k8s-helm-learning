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

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"
VAR_FILE="${VAR_FILE:-vars/prod.tfvars}"

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
  VAR_FILE              Var file under devops/terraform/ (default: vars/prod.tfvars)
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

cmd=(terraform -chdir="${TF_DIR}" plan -var-file="${VAR_FILE}")
if ((${#TARGETS[@]})); then
  for t in "${TARGETS[@]}"; do
    cmd+=( -target="${t}" )
  done
fi

echo "==> terraform plan -var-file=${VAR_FILE}"
exec "${cmd[@]}"
