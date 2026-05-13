#!/bin/bash
set -euo pipefail

# Usage:
#   ./scripts/k8s-rollout-history.sh -n workbench-system workbench-api
#   ./scripts/k8s-rollout-history.sh workbench-api workbench-worker
#   ./scripts/k8s-rollout-history.sh -n workbench-system -r 3 workbench-api

NAMESPACE="workbench-system"
REVISION=""
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
    -r|--revision)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --revision"
        exit 1
      fi
      REVISION="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-n <namespace>] [-r <revision>] <deployment> [deployment ...]"
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
  echo "Usage: $0 [-n <namespace>] [-r <revision>] <deployment> [deployment ...]"
  exit 1
fi

echo "Namespace: ${NAMESPACE}"
echo "Viewing rollout history:"

for deploy in "${DEPLOYMENTS[@]}"; do
  echo
  echo "== ${deploy} =="
  if [[ -n "${REVISION}" ]]; then
    kubectl rollout history deployment/"${deploy}" -n "${NAMESPACE}" --revision="${REVISION}"
  else
    kubectl rollout history deployment/"${deploy}" -n "${NAMESPACE}"
  fi
done

