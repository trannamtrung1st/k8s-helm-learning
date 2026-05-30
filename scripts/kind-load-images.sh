#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/docker-buildx.sh
source "${ROOT}/scripts/lib/docker-buildx.sh"

# Load Docker images from the host into a kind cluster (containerd on kind nodes).
#
# Usage:
#   ./scripts/kind-load-images.sh
#   ./scripts/kind-load-images.sh --cluster workbench-0
#   ./scripts/kind-load-images.sh --cluster workbench-0 image1:tag image2:tag
#   ./scripts/kind-load-images.sh --all-local
#   ./scripts/kind-load-images.sh --all-local --prefix workbenchacr77.azurecr.io/

CLUSTER_NAME="workbench-0"
ALL_LOCAL=false
PREFIX="workbenchacr77.azurecr.io/"
INCLUDE_JOBS="${INCLUDE_JOBS:-1}"

usage() {
  cat <<'EOF'
Usage: ./scripts/kind-load-images.sh [options] [IMAGE ...]

Load images from the local Docker daemon into a kind cluster (all nodes).

Options:
  --cluster <name>   kind cluster name (default: workbench-0)
  --all-local        Load every local image matching --prefix
  --prefix <repo>    Repository prefix for --all-local (default: workbenchacr77.azurecr.io/)
  -h, --help         Show this help

Default (no args): workbench app images at workbenchacr77.azurecr.io (matches compose + Helm).
EOF
}

normalize_cluster_name() {
  local name="$1"
  name="${name#kind-}"
  echo "${name}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      [[ $# -ge 2 ]] || { echo "Missing value for --cluster" >&2; exit 1; }
      CLUSTER_NAME="$(normalize_cluster_name "$2")"
      shift 2
      ;;
    --all-local)
      ALL_LOCAL=true
      shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || { echo "Missing value for --prefix" >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if ! command -v kind >/dev/null 2>&1; then
  echo "kind is not installed or not on PATH." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not on PATH." >&2
  exit 1
fi

CLUSTER_NAME="$(normalize_cluster_name "${CLUSTER_NAME}")"

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  echo "kind cluster '${CLUSTER_NAME}' not found." >&2
  kind get clusters 2>/dev/null | sed 's/^/  /' >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  IMAGES=("$@")
elif [[ "${ALL_LOCAL}" == "true" ]]; then
  IMAGES=()
  while IFS= read -r image; do
    [[ -n "${image}" ]] && IMAGES+=("${image}")
  done < <(docker image ls --format '{{.Repository}}:{{.Tag}}' | awk -v p="${PREFIX}" '$0 !~ /<none>:/ && index($0,p)==1')
  if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "No local images found with prefix: ${PREFIX}" >&2
    exit 1
  fi
else
  IMAGES=()
  while IFS= read -r image; do
    [[ -n "${image}" ]] && IMAGES+=("${image}")
  done < <(workbench_app_images "${INCLUDE_JOBS}")
fi

echo "Target kind cluster: ${CLUSTER_NAME}"
echo "Loading ${#IMAGES[@]} image(s):"
for image in "${IMAGES[@]}"; do
  echo " - ${image}"
  kind load docker-image "${image}" --name "${CLUSTER_NAME}"
done

echo "Done."
