#!/bin/bash
set -euo pipefail

# Usage:
#   ./scripts/kind-load-images.sh
#   ./scripts/kind-load-images.sh --cluster kind-workbench-0
#   ./scripts/kind-load-images.sh --cluster kind-workbench-0 image1:tag image2:tag
#   ./scripts/kind-load-images.sh --all-local
#   ./scripts/kind-load-images.sh --all-local --prefix workbench/

CLUSTER_NAME="workbench-0"
ALL_LOCAL="true"
PREFIX="workbench/"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --cluster"
        exit 1
      fi
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --all-local)
      ALL_LOCAL="true"
      shift
      ;;
    --prefix)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --prefix"
        exit 1
      fi
      PREFIX="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [--cluster <kind-cluster-name>] [--all-local] [--prefix <repo-prefix>] [image ...]"
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if ! command -v kind >/dev/null 2>&1; then
  echo "kind command not found."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found."
  exit 1
fi

if [[ "${ALL_LOCAL}" == "true" ]]; then
  IMAGES=()
  while IFS= read -r image; do
    [[ -n "${image}" ]] && IMAGES+=("${image}")
  done < <(docker image ls --format '{{.Repository}}:{{.Tag}}' | awk -v p="${PREFIX}" '$0 !~ /<none>:/ && index($0,p)==1')
  if [[ ${#IMAGES[@]} -eq 0 ]]; then
    echo "No local images found with prefix: ${PREFIX}"
    exit 1
  fi
elif [[ $# -eq 0 ]]; then
  # Default app images used in this repo.
  IMAGES=(
    "workbench/workbench-api:1.0.0-rc1"
    "workbench/workbench-worker:1.0.0-rc1"
  )
else
  IMAGES=("$@")
fi

echo "Target kind cluster: ${CLUSTER_NAME}"
echo "Loading images:"
for image in "${IMAGES[@]}"; do
  echo " - ${image}"
  kind load docker-image "${image}" --name "${CLUSTER_NAME}"
done

echo "Done."
