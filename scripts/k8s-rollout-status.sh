#!/bin/bash
set -euo pipefail

# Usage:
#   ./scripts/k8s-rollout-status.sh -n workbench-apps workbench-api
#   ./scripts/k8s-rollout-status.sh workbench-api workbench-worker
#   ./scripts/k8s-rollout-status.sh -n workbench-apps --timeout 180s workbench-api

NAMESPACE="workbench-apps"
TIMEOUT=""
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
    -t|--timeout)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --timeout"
        exit 1
      fi
      TIMEOUT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-n <namespace>] [-t <timeout>] <deployment> [deployment ...]"
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
  echo "Usage: $0 [-n <namespace>] [-t <timeout>] <deployment> [deployment ...]"
  exit 1
fi

echo "Namespace: ${NAMESPACE}"
echo "Checking rollout status for deployments:"

for deploy in "${DEPLOYMENTS[@]}"; do
  echo " - ${deploy}"
  if [[ -n "${TIMEOUT}" ]]; then
    kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout="${TIMEOUT}"
  else
    kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}"
  fi
done

echo "Done."
