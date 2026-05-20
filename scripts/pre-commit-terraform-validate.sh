#!/bin/bash
# Pre-commit: terraform init (no remote backend) + validate.
# Uses vars/prod.tfvars when present; otherwise terraform.tfvars or inline placeholders.
# Does not configure the Azure remote state backend (validate does not need state).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"
VAR_FILE="${PRE_COMMIT_TFVARS:-vars/prod.tfvars}"

echo "==> terraform init -backend=false (${TF_DIR})"
terraform -chdir="${TF_DIR}" init -backend=false -input=false

if [[ -f "${TF_DIR}/${VAR_FILE}" ]]; then
  echo "==> terraform validate -var-file=${VAR_FILE}"
  terraform -chdir="${TF_DIR}" validate -var-file="${VAR_FILE}"
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
