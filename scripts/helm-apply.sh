#!/bin/bash
set -euo pipefail

# Update umbrella subchart dependencies, then upgrade/install the local Workbench stack.
# Run from repository root. Requires helm and kubectl context.
#
#   ./scripts/helm-apply.sh
#   ./scripts/helm-apply.sh --dry-run
#   ./scripts/helm-apply.sh --dry-run=server
#
# Override release, namespace, or history limit:
#   HELM_RELEASE=my-release HELM_NAMESPACE=my-ns ./scripts/helm-apply.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/devops/workbench-umbrella"
VALUES_PLATFORM="${ROOT}/devops/platform/values/global-values.yaml"
VALUES_CLUSTER="${ROOT}/devops/clusters/local/global-values.yaml"
RELEASE="${HELM_RELEASE:-workbench-umbrella-local}"
NAMESPACE="${HELM_NAMESPACE:-workbench-platform}"
HISTORY_MAX="${HELM_HISTORY_MAX:-5}"

extra_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      extra_args+=(--dry-run=server)
      shift
      ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

helm dependency update "${CHART}"

cmd=(
  helm upgrade "${RELEASE}" "${CHART}"
  --server-side=true
  --install
  -n "${NAMESPACE}"
  --create-namespace
  -f "${VALUES_PLATFORM}"
  -f "${VALUES_CLUSTER}"
  --history-max "${HISTORY_MAX}"
)
if ((${#extra_args[@]} > 0)); then
  cmd+=("${extra_args[@]}")
fi

exec "${cmd[@]}"
