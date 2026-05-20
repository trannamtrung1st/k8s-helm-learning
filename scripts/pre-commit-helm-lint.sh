#!/bin/bash
# Pre-commit: refresh umbrella dependencies and lint/template with the standard values chain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/devops/workbench-umbrella"
VALUES_PLATFORM="${ROOT}/devops/platform/values/global-values.yaml"
VALUES_CLUSTER="${ROOT}/devops/clusters/local/global-values.yaml"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is not installed or not on PATH." >&2
  exit 1
fi

for f in "${VALUES_PLATFORM}" "${VALUES_CLUSTER}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Missing values file: ${f}" >&2
    exit 1
  fi
done

"${ROOT}/scripts/helm-dependency-update.sh"

LINT_ARGS=(
  helm lint "${CHART}"
  -f "${VALUES_PLATFORM}"
  -f "${VALUES_CLUSTER}"
  --strict
)

echo "==> ${LINT_ARGS[*]}"
"${LINT_ARGS[@]}"

echo "==> helm template (smoke) ${CHART}"
helm template pre-commit-smoke "${CHART}" \
  -f "${VALUES_PLATFORM}" \
  -f "${VALUES_CLUSTER}" \
  >/dev/null

echo "Helm lint and template smoke check passed."
