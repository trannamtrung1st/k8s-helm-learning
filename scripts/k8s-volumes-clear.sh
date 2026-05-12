#!/bin/bash
set -euo pipefail

# Paths used by local PersistentVolumes in the kind node filesystem.
VOLUME_PATHS=(
  "/mnt/disks/workbench-postgres-db"
  "/mnt/disks/workbench-rabbitmq"
)

KIND_NODE="workbench-0-control-plane"
CONFIRMED="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      CONFIRMED="true"
      shift
      ;;
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
      echo "Usage: $0 --yes [--node <kind-node-container-name>]"
      exit 1
      ;;
  esac
done

if [[ "${CONFIRMED}" != "true" ]]; then
  echo "This will delete ALL contents under:"
  for path in "${VOLUME_PATHS[@]}"; do
    echo " - ${path}"
  done
  echo
  echo "Kind node: ${KIND_NODE}"
  echo "Re-run with --yes to confirm."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found."
  exit 1
fi

echo "Clearing volume directories in kind node: ${KIND_NODE}"
for path in "${VOLUME_PATHS[@]}"; do
  echo " - ${path}"
  docker exec "${KIND_NODE}" sh -lc "mkdir -p '${path}' && rm -rf '${path}/'*"
done

echo "Done."
