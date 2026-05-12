#!/bin/bash
set -euo pipefail

# Usage:
#   ./scripts/k8s-restart-deployments.sh -n workbench-system workbench-api
#   ./scripts/k8s-restart-deployments.sh -n workbench-system workbench-api workbench-worker
#   ./scripts/k8s-restart-deployments.sh workbench-api   # defaults to workbench-system

NAMESPACE="workbench-system"
DEPLOYMENTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--namespace)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --namespace"
        exit 1
      fi
      NAMESPACE="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-n <namespace>] <deployment> [deployment ...]"
      exit 0
      ;;
    *)
      DEPLOYMENTS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#DEPLOYMENTS[@]} -eq 0 ]]; then
  echo "No deployment names provided."
  echo "Usage: $0 [-n <namespace>] <deployment> [deployment ...]"
  exit 1
fi

echo "Namespace: ${NAMESPACE}"
echo "Restarting deployments:"
for deploy in "${DEPLOYMENTS[@]}"; do
  echo " - ${deploy}"
  kubectl rollout restart deployment/"${deploy}" -n "${NAMESPACE}"
done

echo "Waiting for rollout status..."
for deploy in "${DEPLOYMENTS[@]}"; do
  kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}"
done

echo "Done."
