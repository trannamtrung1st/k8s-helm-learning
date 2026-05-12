#!/bin/bash
set -euo pipefail

# Paths used by local PersistentVolumes in the kind node filesystem.
# By default, runs `docker exec` on every Kubernetes node labeled
# workbench.io/infra-node=true (same name as the kind node container).
# Override with --node <name> for a single container.

VOLUME_PATHS=(
  "/mnt/disks/workbench-postgres-db"
  "/mnt/disks/workbench-rabbitmq"
)

INFRA_NODE_LABEL="workbench.io/infra-node=true"
KIND_NODE_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --node"
        exit 1
      fi
      KIND_NODE_OVERRIDE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--node <kind-node-container-name>]"
      echo "Without --node: uses kubectl to find nodes labeled ${INFRA_NODE_LABEL}"
      exit 1
      ;;
  esac
done

if ! command -v docker >/dev/null 2>&1; then
  echo "docker command not found."
  exit 1
fi

KIND_NODES=()
if [[ -n "${KIND_NODE_OVERRIDE}" ]]; then
  KIND_NODES=("${KIND_NODE_OVERRIDE}")
else
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found. Install kubectl, or pass an explicit --node <kind-container-name>."
    exit 1
  fi
  while IFS= read -r n; do
    [[ -n "${n}" ]] && KIND_NODES+=("${n}")
  done < <(kubectl get nodes -l "${INFRA_NODE_LABEL}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ ${#KIND_NODES[@]} -eq 0 ]]; then
    echo "No nodes labeled ${INFRA_NODE_LABEL}."
    echo "Label your volume host(s), then re-run. Example:"
    echo "  kubectl label node <node-name> workbench.io/infra-node=true --overwrite"
    exit 1
  fi
fi

echo "Initializing volume directories on kind node(s): ${KIND_NODES[*]}"
for kind_node in "${KIND_NODES[@]}"; do
  echo "--- ${kind_node}"
  for path in "${VOLUME_PATHS[@]}"; do
    echo " - ${path}"
    docker exec "${kind_node}" mkdir -p "${path}"
  done
done

echo "Done."
