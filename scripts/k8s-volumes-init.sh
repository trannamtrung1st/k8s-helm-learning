#!/bin/bash
set -euo pipefail

# Paths used by local PersistentVolumes in the kind node filesystem.
VOLUME_PATHS=(
  "/mnt/disks/workbench-postgres-db"
  "/mnt/disks/workbench-rabbitmq"
)

KIND_NODE="workbench-0-control-plane"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --node"
        exit 1
      fi
      KIND_NODE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--node <kind-node-container-name>]"
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found."
  exit 1
fi

echo "Initializing volume directories in kind node: ${KIND_NODE}"
for path in "${VOLUME_PATHS[@]}"; do
  echo " - ${path}"
  docker exec "${KIND_NODE}" mkdir -p "${path}"
done

echo "Done."
