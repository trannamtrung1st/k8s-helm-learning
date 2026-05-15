#!/bin/bash
set -euo pipefail

# Port-forward a Kubernetes resource (Service, Pod, Deployment, StatefulSet, …).
#
# Usage:
#   ./scripts/k8s-port-forward.sh svc/workbench-api 8080:80
#   ./scripts/k8s-port-forward.sh -n workbench-apps svc/workbench-api 8080:80
#   ./scripts/k8s-port-forward.sh -n workbench-infra pod/workbench-rabbitmq-0 15672:15672
#   ./scripts/k8s-port-forward.sh -n workbench-infra sts/workbench-redis 6379:6379
#   ./scripts/k8s-port-forward.sh --address 0.0.0.0 -n workbench-apps svc/workbench-api 8080:80
#
# If -n is omitted, kubectl uses your current context namespace.
# Resource must be TYPE/NAME (kubectl shorthand: svc, deploy, pod, sts, …).

NAMESPACE=""
ADDRESS="127.0.0.1"

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
    -a|--address)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --address"
        exit 1
      fi
      ADDRESS="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [-n <namespace>] [-a <bind-address>] <type/name> <local:remote> [<local:remote> ...]"
      echo "Examples:"
      echo "  $0 -n workbench-apps svc/workbench-api 8080:80"
      echo "  $0 -n workbench-infra pod/workbench-rabbitmq-0 15672:15672"
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 2 ]]; then
  echo "Not enough arguments."
  echo "Usage: $0 [-n <namespace>] [-a <bind-address>] <type/name> <local:remote> [<local:remote> ...]"
  exit 1
fi

RESOURCE="$1"
shift
PORTS=("$@")

if [[ "${RESOURCE}" != */* ]]; then
  echo "Resource must be TYPE/NAME (e.g. svc/workbench-api, pod/my-pod-0)."
  exit 1
fi

echo "Port-forward ${RESOURCE} ${PORTS[*]}"
if [[ -n "${NAMESPACE}" ]]; then
  echo "Namespace: ${NAMESPACE}"
else
  echo "Namespace: (current context)"
fi
echo "Bind address: ${ADDRESS}"
echo "Press Ctrl+C to stop."

if [[ -n "${NAMESPACE}" ]]; then
  kubectl port-forward -n "${NAMESPACE}" --address="${ADDRESS}" "${RESOURCE}" "${PORTS[@]}"
else
  kubectl port-forward --address="${ADDRESS}" "${RESOURCE}" "${PORTS[@]}"
fi
