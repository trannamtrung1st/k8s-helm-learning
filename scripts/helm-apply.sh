#!/bin/bash
set -euo pipefail

# Update umbrella subchart dependencies, then upgrade/install the local Workbench stack.
# Run from repository root. Requires helm and kubectl context.
#
#   ./scripts/helm-apply.sh
#   ./scripts/helm-apply.sh --dry-run
#   ./scripts/helm-apply.sh --dry-run=server
#
# Override release, namespace, cluster overlay, or history limit:
#   HELM_CLUSTER=aks HELM_RELEASE=workbench-umbrella-aks ./scripts/helm-apply.sh
#   HELM_RELEASE=my-release HELM_NAMESPACE=my-ns ./scripts/helm-apply.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/devops/workbench-umbrella"
HELM_CLUSTER="${HELM_CLUSTER:-local}"
VALUES_PLATFORM="${ROOT}/devops/platform/values/global-values.yaml"
VALUES_CLUSTER="${ROOT}/devops/clusters/${HELM_CLUSTER}/global-values.yaml"
RELEASE="${HELM_RELEASE:-workbench-umbrella-${HELM_CLUSTER}}"
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
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

if [[ ! -f "${VALUES_CLUSTER}" ]]; then
  echo "Missing cluster values: ${VALUES_CLUSTER} (set HELM_CLUSTER or create the file)" >&2
  exit 1
fi

"${ROOT}/scripts/helm-dependency-update.sh"

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
