#!/bin/bash
set -euo pipefail

# Wizard-style helper to add or remove labels on Kubernetes Nodes.
#
# Requires: kubectl, current context pointing at the target cluster.
#
# Non-interactive:
#   ./scripts/k8s-node-label-wizard.sh label --node NAME key=value [key=value ...]
#   ./scripts/k8s-node-label-wizard.sh unlabel --node NAME KEY [KEY ...]
#   ./scripts/k8s-node-label-wizard.sh label-all key=value [--yes]

require_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is not installed or not on PATH."
    exit 1
  fi
}

WIZ_NODES=()

load_nodes() {
  WIZ_NODES=()
  while IFS= read -r n; do
    [[ -n "${n}" ]] && WIZ_NODES+=("${n}")
  done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
}

list_nodes_labels() {
  require_kubectl
  echo ""
  echo "=== Nodes (wide + labels) ==="
  if ! kubectl get nodes -o wide --show-labels 2>/dev/null; then
    kubectl get nodes 2>/dev/null || echo "Could not list nodes (check kubectl context)."
  fi
  echo ""
}

# Prints chosen node name to stdout; menus/errors to stderr. Exit 1 on failure.
pick_one_node() {
  load_nodes
  local count="${#WIZ_NODES[@]}"
  if [[ "${count}" -eq 0 ]]; then
    echo "No nodes found (check context: kubectl config current-context)." >&2
    return 1
  fi
  local i
  for ((i = 0; i < count; i++)); do
    echo "  $((i + 1))) ${WIZ_NODES[i]}" >&2
  done
  local pick
  printf 'Choose node [1-%s]: ' "${count}" >&2
  read -r pick
  if [[ ! "${pick}" =~ ^[0-9]+$ ]] || [[ "${pick}" -lt 1 || "${pick}" -gt "${count}" ]]; then
    echo "Invalid selection." >&2
    return 1
  fi
  echo "${WIZ_NODES[$((pick - 1))]}"
}

prompt_yes_no() {
  local reply
  read -r -p "${1} [y/N]: " reply
  reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

validate_kv() {
  local pair="$1"
  if [[ "${pair}" != *=* ]]; then
    echo "Expected key=value, got: ${pair}"
    return 1
  fi
}

add_labels_interactive() {
  require_kubectl
  local node
  node="$(pick_one_node)" || return

  echo "" >&2
  echo "Selected node: ${node}" >&2
  kubectl get node "${node}" --show-labels >&2 || true

  local pair
  while true; do
    read -r -p "Label as key=value (empty line to finish): " pair
    [[ -z "${pair}" ]] && break
    validate_kv "${pair}" || continue
    if prompt_yes_no "Apply ${pair} with --overwrite?"; then
      kubectl label node "${node}" "${pair}" --overwrite
    else
      kubectl label node "${node}" "${pair}" 2>/dev/null || {
        echo "Label failed (exists?). Retry with overwrite=yes, or fix the key/value."
      }
    fi
  done
  echo "Done."
}

remove_label_interactive() {
  require_kubectl
  local node
  node="$(pick_one_node)" || return

  echo "" >&2
  echo "Selected node: ${node}" >&2
  kubectl get node "${node}" --show-labels >&2 || true

  local key
  read -r -p "Label key to remove (e.g. disktype): " key
  if [[ -z "${key}" ]]; then
    echo "Aborted (empty key)."
    return
  fi
  if ! prompt_yes_no "Remove label '${key}' from ${node}?"; then
    echo "Aborted."
    return
  fi
  kubectl label node "${node}" "${key}-"
  echo "Removed label '${key}' from ${node}."
}

label_all_interactive() {
  require_kubectl
  load_nodes
  local count="${#WIZ_NODES[@]}"
  if [[ "${count}" -eq 0 ]]; then
    echo "No nodes found."
    return
  fi

  local pair
  read -r -p "Label key=value to apply to ALL ${count} node(s): " pair
  if [[ -z "${pair}" ]]; then
    echo "Aborted."
    return
  fi
  validate_kv "${pair}" || return

  echo "Nodes: ${WIZ_NODES[*]}"
  if ! prompt_yes_no "Apply ${pair} to every node with --overwrite?"; then
    echo "Aborted."
    return
  fi

  local n
  for n in "${WIZ_NODES[@]}"; do
    echo "Labeling ${n} ..."
    kubectl label node "${n}" "${pair}" --overwrite
  done
  echo "Done."
}

show_help() {
  cat <<EOF
Interactive menu to label or unlabel Kubernetes nodes.

CLI (non-interactive):
  $0 label --node NODE key=value [key=value ...]
  $0 unlabel --node NODE KEY [KEY ...]
  $0 label-all key=value [--yes]   # skip confirmation when --yes

Examples:
  $0
  $0 label --node workbench-0-worker workbench.io/infra-node=true
  $0 unlabel --node workbench-0-worker workbench.io/infra-node
EOF
}

cmd_label() {
  require_kubectl
  local node=""
  local pairs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node)
        node="$2"
        shift 2
        ;;
      *)
        pairs+=("$1")
        shift
        ;;
    esac
  done
  if [[ -z "${node}" || ${#pairs[@]} -eq 0 ]]; then
    echo "Usage: $0 label --node NAME key=value [key=value ...]"
    exit 1
  fi
  local p
  for p in "${pairs[@]}"; do
    validate_kv "${p}" || exit 1
  done
  kubectl label node "${node}" "${pairs[@]}" --overwrite
  echo "Labeled node ${node}."
}

cmd_unlabel() {
  require_kubectl
  local node=""
  local keys=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node)
        node="$2"
        shift 2
        ;;
      *)
        keys+=("$1")
        shift
        ;;
    esac
  done
  if [[ -z "${node}" || ${#keys[@]} -eq 0 ]]; then
    echo "Usage: $0 unlabel --node NAME KEY [KEY ...]"
    exit 1
  fi
  local args=()
  local k
  for k in "${keys[@]}"; do
    if [[ "${k}" == *- ]]; then
      args+=("${k}")
    else
      args+=("${k}-")
    fi
  done
  kubectl label node "${node}" "${args[@]}"
  echo "Updated node ${node}."
}

cmd_label_all() {
  require_kubectl
  local pair=""
  local yes="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        yes="true"
        shift
        ;;
      *)
        if [[ -n "${pair}" ]]; then
          echo "Only one key=value is allowed (got extra: $1)"
          exit 1
        fi
        pair="$1"
        shift
        ;;
    esac
  done
  if [[ -z "${pair}" ]]; then
    echo "Usage: $0 label-all key=value [--yes]"
    exit 1
  fi
  validate_kv "${pair}" || exit 1
  load_nodes
  if [[ ${#WIZ_NODES[@]} -eq 0 ]]; then
    echo "No nodes found."
    exit 1
  fi
  if [[ "${yes}" != "true" ]]; then
    echo "Will label ${#WIZ_NODES[@]} node(s) with: ${pair}"
    read -r -p "Type YES to confirm: " conf
    [[ "${conf}" == "YES" ]] || { echo "Aborted."; exit 1; }
  fi
  local n
  for n in "${WIZ_NODES[@]}"; do
    kubectl label node "${n}" "${pair}" --overwrite
  done
  echo "Done."
}

main_menu() {
  while true; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Node label wizard"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Current context: $(kubectl config current-context 2>/dev/null || echo '(unknown)')"
    echo ""
    echo "  1) List nodes and labels"
    echo "  2) Add / replace label on one node"
    echo "  3) Remove a label from one node"
    echo "  4) Add / replace the same label on ALL nodes"
    echo "  0) Exit"
    echo ""
    local choice
    read -r -p "Choose [0-4]: " choice
    case "${choice}" in
      1) list_nodes_labels ;;
      2) add_labels_interactive ;;
      3) remove_label_interactive ;;
      4) label_all_interactive ;;
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

case "${1:-}" in
  -h|--help|help)
    show_help
    exit 0
    ;;
  label)
    shift
    cmd_label "$@"
    ;;
  unlabel)
    shift
    cmd_unlabel "$@"
    ;;
  label-all)
    shift
    cmd_label_all "$@"
    ;;
  "")
    require_kubectl
    main_menu
    ;;
  *)
    echo "Unknown command: $1"
    show_help
    exit 1
    ;;
esac
