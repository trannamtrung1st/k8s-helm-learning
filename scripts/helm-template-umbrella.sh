#!/bin/bash
# Render devops/workbench-umbrella with the standard values chain.
#
# From repository root:
#   ./scripts/helm-template-umbrella.sh
#   ./scripts/helm-template-umbrella.sh --cluster aks
#   ./scripts/helm-template-umbrella.sh --stdout
#   ./scripts/helm-template-umbrella.sh -o .temp/my-render.yaml
#
# Environment:
#   HELM_CLUSTER          Cluster overlay name (default: local)
#   HELM_RELEASE          Logical release name for helm template (default: workbench-umbrella-<cluster>)
#   HELM_NAMESPACE        Optional namespace (-n) for rendered resources

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="${ROOT}/devops/workbench-umbrella"
HELM_CLUSTER="${HELM_CLUSTER:-local}"
HELM_RELEASE="${HELM_RELEASE:-}"
HELM_NAMESPACE="${HELM_NAMESPACE:-}"
OUTPUT=""
WRITE_STDOUT=0
UPDATE_DEPS=0

list_helm_clusters() {
  find "${ROOT}/devops/clusters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  echo ""
  echo "Options:"
  echo "  --cluster <name>      Values overlay under devops/clusters/<name>/ (default: local)"
  echo "  -o, --output <path>   Write rendered manifests to this file (default: .temp/workbench-umbrella-<cluster>.yaml)"
  echo "  --stdout              Write to stdout instead of a file"
  echo "  --release <name>      Helm release name (default: workbench-umbrella-<cluster>)"
  echo "  -n, --namespace <ns>  Pass -n to helm template"
  echo "  --update-deps         Run scripts/helm-dependency-update.sh before templating"
  echo "  -h, --help            Show this help"
  echo ""
  echo "Available clusters:"
  list_helm_clusters | sed 's/^/  /'
}

extra_args=()
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
    -o|--output)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --output" >&2
        exit 1
      fi
      OUTPUT="$2"
      shift 2
      ;;
    --stdout)
      WRITE_STDOUT=1
      shift
      ;;
    --release)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --release" >&2
        exit 1
      fi
      HELM_RELEASE="$2"
      shift 2
      ;;
    -n|--namespace)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Missing value for --namespace" >&2
        exit 1
      fi
      HELM_NAMESPACE="$2"
      shift 2
      ;;
    --update-deps)
      UPDATE_DEPS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      extra_args+=("$1")
      shift
      ;;
  esac
done

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is not installed or not on PATH." >&2
  exit 1
fi

VALUES_PLATFORM="${ROOT}/devops/platform/values/global-values.yaml"
VALUES_CLUSTER="${ROOT}/devops/clusters/${HELM_CLUSTER}/global-values.yaml"
VALUES_LOCAL_CA="${ROOT}/devops/clusters/${HELM_CLUSTER}/local-ca.values.yaml"
RELEASE="${HELM_RELEASE:-workbench-umbrella-${HELM_CLUSTER}}"

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

if [[ "${UPDATE_DEPS}" == "1" ]]; then
  "${ROOT}/scripts/helm-dependency-update.sh"
fi

template_args=(
  helm template "${RELEASE}" "${CHART}"
  -f "${VALUES_PLATFORM}"
  -f "${VALUES_CLUSTER}"
)
if [[ -f "${VALUES_LOCAL_CA}" ]]; then
  template_args+=(-f "${VALUES_LOCAL_CA}")
fi
if [[ -n "${HELM_NAMESPACE}" ]]; then
  template_args+=(-n "${HELM_NAMESPACE}")
fi
if ((${#extra_args[@]} > 0)); then
  template_args+=("${extra_args[@]}")
fi

if [[ "${WRITE_STDOUT}" == "1" ]]; then
  echo "==> ${template_args[*]}"
  "${template_args[@]}"
  exit 0
fi

if [[ -z "${OUTPUT}" ]]; then
  OUTPUT="${ROOT}/.temp/workbench-umbrella-${HELM_CLUSTER}.yaml"
fi
if [[ "${OUTPUT}" != /* ]]; then
  OUTPUT="${ROOT}/${OUTPUT}"
fi

mkdir -p "$(dirname "${OUTPUT}")"

echo "==> ${template_args[*]} > ${OUTPUT}"
"${template_args[@]}" > "${OUTPUT}"
echo "Wrote ${OUTPUT}"
