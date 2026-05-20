#!/bin/bash
# Pre-commit: terraform init (local backend) + validate with placeholder variables.
# Does not use remote state or real subscription credentials.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/devops/terraform"

echo "==> terraform init -backend=false (${TF_DIR})"
terraform -chdir="${TF_DIR}" init -backend=false -input=false

echo "==> terraform validate (placeholder -var values)"
terraform -chdir="${TF_DIR}" validate \
  -var='tenant_id=00000000-0000-0000-0000-000000000001' \
  -var='subscription_id=00000000-0000-0000-0000-000000000002' \
  -var='client_id=00000000-0000-0000-0000-000000000003' \
  -var='use_oidc=false'
