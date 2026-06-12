#!/bin/bash
# Pre-commit: refresh umbrella dependencies and lint/template with the standard values chain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/devops/umbrellas/workbench-umbrella"
HELM_CLUSTER="${HELM_CLUSTER:-local}"
VALUES_PLATFORM="${ROOT}/devops/platform/platform-values/global-values.yaml"

list_helm_clusters() {
  find "${ROOT}/devops/clusters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

usage() {
  sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Usage: $0 [--cluster <name>]"
  echo ""
  echo "Available clusters:"
  list_helm_clusters | sed 's/^/  /'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --cluster" >&2
        exit 1
      fi
      HELM_CLUSTER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

VALUES_CLUSTER="${ROOT}/devops/clusters/${HELM_CLUSTER}/global-values.yaml"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is not installed or not on PATH." >&2
  exit 1
fi

for f in "${VALUES_PLATFORM}" "${VALUES_CLUSTER}"; do
  if [[ ! -f "${f}" ]]; then
    echo "Missing values file: ${f}" >&2
    if [[ "${f}" == "${VALUES_CLUSTER}" ]]; then
      echo "Set --cluster or HELM_CLUSTER. Available:" >&2
      list_helm_clusters | sed 's/^/  /' >&2
    fi
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
