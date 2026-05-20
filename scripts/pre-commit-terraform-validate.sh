#!/bin/bash
# Pre-commit: terraform init (no remote backend) + validate.
# Uses vars/prod.tfvars when present; auto-includes vars/secrets.tfvars when present.
# Does not configure the Azure remote state backend (validate does not need state).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"
VAR_FILE="${PRE_COMMIT_TFVARS:-vars/prod.tfvars}"
# shellcheck source=scripts/lib/terraform-varfiles.sh
source "${ROOT}/scripts/lib/terraform-varfiles.sh"

echo "==> terraform init -backend=false (${TF_DIR})"
terraform -chdir="${TF_DIR}" init -backend=false -input=false

if [[ -f "${TF_DIR}/${VAR_FILE}" ]]; then
  terraform_varfiles_build "${TF_DIR}"
  echo "==> terraform validate -var-file=$(terraform_varfiles_label "${TF_DIR}")"
  terraform -chdir="${TF_DIR}" validate "${TERRAFORM_VARFILES[@]}"
elif [[ -f "${TF_DIR}/terraform.tfvars" ]]; then
  echo "==> terraform validate (auto-loaded terraform.tfvars)"
  terraform -chdir="${TF_DIR}" validate
else
  echo "==> terraform validate (inline placeholder -var; no tfvars found)"
  terraform -chdir="${TF_DIR}" validate \
    -var='tenant_id=00000000-0000-0000-0000-000000000001' \
    -var='subscription_id=00000000-0000-0000-0000-000000000002' \
    -var='client_id=00000000-0000-0000-0000-000000000003' \
    -var='use_oidc=false'
fi
