#!/bin/bash
set -euo pipefail

# Usage:
#   ./scripts/k8s-events.sh                 # all namespaces
#   ./scripts/k8s-events.sh workbench-infra # one namespace
#   ./scripts/k8s-events.sh all Failed      # filter by keyword

NAMESPACE="${1:-all}"
FILTER="${2:-}"

if [[ "${NAMESPACE}" == "all" ]]; then
  CMD=(kubectl get events -A --sort-by=.metadata.creationTimestamp)
else
  CMD=(kubectl get events -n "${NAMESPACE}" --sort-by=.metadata.creationTimestamp)
fi

if [[ -n "${FILTER}" ]]; then
  if command -v rg >/dev/null 2>&1; then
    "${CMD[@]}" | rg -i "${FILTER}"
  else
    "${CMD[@]}" | grep -i "${FILTER}"
  fi
else
  "${CMD[@]}"
fi
