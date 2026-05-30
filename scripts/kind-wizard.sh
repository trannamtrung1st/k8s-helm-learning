#!/bin/bash
set -euo pipefail

# Interactive helper for kind: list clusters, create (single or multi-node),
# delete, or delete-and-recreate. Matches repo defaults (cluster name workbench-0).
#
# Run from anywhere; kind uses your Docker context. After create, use:
#   kubectl config use-context kind-<cluster-name>
#   ./scripts/kind-load-images.sh --cluster <cluster-name>

DEFAULT_CLUSTER_NAME="workbench-0"
KIND_API_VERSION="kind.x-k8s.io/v1alpha4"

require_kind() {
  if ! command -v kind >/dev/null 2>&1; then
    echo "kind is not installed or not on PATH."
    exit 1
  fi
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed or not on PATH."
    exit 1
  fi
}

cluster_exists() {
  local name="$1"
  kind get clusters 2>/dev/null | grep -qx "${name}"
}

list_clusters() {
  echo ""
  echo "=== kind clusters ==="
  if ! kind get clusters 2>/dev/null | grep -q .; then
    echo "(none)"
  else
    kind get clusters
  fi
  echo ""
  echo "kubectl contexts (kind-*):"
  if command -v kubectl >/dev/null 2>&1; then
    local ctxs
    ctxs="$(kubectl config get-contexts -o name 2>/dev/null || true)"
    if echo "${ctxs}" | grep -q '^kind-'; then
      echo "${ctxs}" | grep '^kind-'
    else
      echo "(none matching kind-*)"
    fi
  else
    echo "(kubectl not installed)"
  fi
  echo ""
}

prompt_nonempty() {
  local prompt="$1"
  local default="$2"
  local out
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " out
    echo "${out:-${default}}"
  else
    while true; do
      read -r -p "${prompt}: " out
      if [[ -n "${out}" ]]; then
        echo "${out}"
        return
      fi
      echo "Value required."
    done
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default_n="${2:-n}"
  local reply
  read -r -p "${prompt} [y/N]: " reply
  reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

prompt_workers() {
  local default="${1:-0}"
  local raw
  while true; do
    read -r -p "Number of worker nodes (0 = control-plane only) [${default}]: " raw
    raw="${raw:-${default}}"
    if [[ "${raw}" =~ ^[0-9]+$ ]]; then
      echo "${raw}"
      return
    fi
    echo "Enter a non-negative integer."
  done
}

write_kind_config() {
  local workers="$1"
  local file="$2"
  {
    echo "kind: Cluster"
    echo "apiVersion: ${KIND_API_VERSION}"
    echo "nodes:"
    echo "  - role: control-plane"
    local i
    for ((i = 0; i < workers; i++)); do
      echo "  - role: worker"
    done
  } >"${file}"
}

# macOS mktemp requires trailing XXXXXX (no .yaml suffix after placeholders).
kind_wizard_mktemp_config() {
  mktemp "${TMPDIR:-/tmp}/kind-wizard.XXXXXX"
}

create_cluster_interactive() {
  require_kind
  require_docker

  local name workers tmp
  name="$(prompt_nonempty "Cluster name" "${DEFAULT_CLUSTER_NAME}")"
  workers="$(prompt_workers 0)"

  if cluster_exists "${name}"; then
    echo "Cluster '${name}' already exists."
    if prompt_yes_no "Delete it and create a new one with these settings?"; then
      echo "Deleting cluster '${name}'..."
      kind delete cluster --name "${name}"
    else
      echo "Aborted."
      return
    fi
  fi

  echo ""
  echo "Will create:"
  echo "  name:    ${name}"
  echo "  workers: ${workers}"
  echo ""

  if ! prompt_yes_no "Proceed?"; then
    echo "Aborted."
    return
  fi

  if [[ "${workers}" -eq 0 ]]; then
    kind create cluster --name "${name}"
  else
    tmp="$(kind_wizard_mktemp_config)"
    write_kind_config "${workers}" "${tmp}"
    echo "Using config (${tmp}):"
    cat "${tmp}"
    kind create cluster --name "${name}" --config "${tmp}"
    rm -f "${tmp}"
  fi

  echo ""
  echo "Cluster '${name}' is ready."
  echo "  kubectl config use-context kind-${name}"
  echo "  ./scripts/kind-load-images.sh --cluster ${name}"
  echo "  ./scripts/kind-e2e-first-run.sh   # full first-run (Helm)"
  echo "  ./scripts/helm-apply.sh           # apply only"
  echo "  ./scripts/kind-e2e-first-run.sh --k8s   # legacy Kustomize apply"
  echo ""
}

delete_cluster_interactive() {
  require_kind

  list_clusters
  local name
  name="$(prompt_nonempty "Cluster name to DELETE (see list above)" "")"

  if ! cluster_exists "${name}"; then
    echo "No cluster named '${name}'."
    return
  fi

  echo "This will run: kind delete cluster --name ${name}"
  if ! prompt_yes_no "Confirm delete?"; then
    echo "Aborted."
    return
  fi

  kind delete cluster --name "${name}"
  echo "Deleted cluster '${name}'."
  echo ""
}

recreate_cluster_interactive() {
  require_kind
  require_docker

  list_clusters
  local name workers tmp
  name="$(prompt_nonempty "Cluster name to recreate" "${DEFAULT_CLUSTER_NAME}")"

  if cluster_exists "${name}"; then
    echo "Deleting existing cluster '${name}'..."
    kind delete cluster --name "${name}"
  else
    echo "Cluster '${name}' does not exist (will create only)."
  fi

  workers="$(prompt_workers 0)"
  echo ""
  echo "Will create:"
  echo "  name:    ${name}"
  echo "  workers: ${workers}"
  echo ""
  if ! prompt_yes_no "Proceed?"; then
    echo "Aborted."
    return
  fi

  if [[ "${workers}" -eq 0 ]]; then
    kind create cluster --name "${name}"
  else
    tmp="$(kind_wizard_mktemp_config)"
    write_kind_config "${workers}" "${tmp}"
    cat "${tmp}"
    kind create cluster --name "${name}" --config "${tmp}"
    rm -f "${tmp}"
  fi

  echo ""
  echo "Cluster '${name}' is ready."
  echo "  kubectl config use-context kind-${name}"
  echo "  ./scripts/kind-load-images.sh --cluster ${name}"
  echo ""
}

show_help() {
  cat <<EOF
Interactive kind menu (create multi-node cluster, delete, recreate).

Non-interactive (optional):
  $0 create [--name NAME] [--workers N]
  $0 delete --name NAME
  $0 recreate [--name NAME] [--workers N]

Examples:
  $0
  $0 create --name workbench-0 --workers 2
  $0 delete --name workbench-0
  $0 recreate --name workbench-0 --workers 1
EOF
}

cmd_create_cli() {
  require_kind
  require_docker
  local name="${DEFAULT_CLUSTER_NAME}"
  local workers="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        name="$2"
        shift 2
        ;;
      --workers)
        workers="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done
  if [[ ! "${workers}" =~ ^[0-9]+$ ]]; then
    echo "--workers must be a non-negative integer."
    exit 1
  fi
  if cluster_exists "${name}"; then
    echo "Cluster '${name}' already exists. Use: $0 delete --name ${name}"
    exit 1
  fi
  local tmp
  if [[ "${workers}" -eq 0 ]]; then
    kind create cluster --name "${name}"
  else
    tmp="$(kind_wizard_mktemp_config)"
    write_kind_config "${workers}" "${tmp}"
    kind create cluster --name "${name}" --config "${tmp}"
    rm -f "${tmp}"
  fi
  echo "Done. kubectl config use-context kind-${name}"
}

cmd_delete_cli() {
  require_kind
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        name="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done
  if [[ -z "${name}" ]]; then
    echo "Missing --name"
    exit 1
  fi
  kind delete cluster --name "${name}"
  echo "Deleted cluster '${name}'."
}

cmd_recreate_cli() {
  require_kind
  require_docker
  local name="${DEFAULT_CLUSTER_NAME}"
  local workers="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        name="$2"
        shift 2
        ;;
      --workers)
        workers="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done
  if [[ ! "${workers}" =~ ^[0-9]+$ ]]; then
    echo "--workers must be a non-negative integer."
    exit 1
  fi
  if cluster_exists "${name}"; then
    kind delete cluster --name "${name}"
  fi
  local tmp
  if [[ "${workers}" -eq 0 ]]; then
    kind create cluster --name "${name}"
  else
    tmp="$(kind_wizard_mktemp_config)"
    write_kind_config "${workers}" "${tmp}"
    kind create cluster --name "${name}" --config "${tmp}"
    rm -f "${tmp}"
  fi
  echo "Done. kubectl config use-context kind-${name}"
}

main_menu() {
  while true; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  kind cluster wizard"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  1) List clusters"
    echo "  2) Create cluster (name + worker count)"
    echo "  3) Delete cluster"
    echo "  4) Delete and recreate cluster"
    echo "  0) Exit"
    echo ""
    local choice
    read -r -p "Choose [0-4]: " choice
    case "${choice}" in
      1) list_clusters ;;
      2) create_cluster_interactive ;;
      3) delete_cluster_interactive ;;
      4) recreate_cluster_interactive ;;
      0)
        echo "Bye."
        exit 0
        ;;
      *)
        echo "Invalid choice."
        ;;
    esac
  done
}

# --- entry ---

case "${1:-}" in
  -h|--help|help)
    show_help
    exit 0
    ;;
  create)
    shift
    cmd_create_cli "$@"
    ;;
  delete)
    shift
    cmd_delete_cli "$@"
    ;;
  recreate)
    shift
    cmd_recreate_cli "$@"
    ;;
  "")
    main_menu
    ;;
  *)
    echo "Unknown command: $1"
    show_help
    exit 1
    ;;
esac
