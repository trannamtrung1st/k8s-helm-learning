#!/bin/bash
set -euo pipefail

# Recover Workbench Helm releases stuck in failed or pending states.
# Tries rollback to the last deployed revision; if that is not possible, uninstalls
# so ./scripts/helm-apply.sh can run a clean upgrade --install.
#
#   ./scripts/helm-recover.sh
#   ./scripts/helm-recover.sh --cluster local
#   ./scripts/helm-recover.sh --main-only -y
#   ./scripts/helm-recover.sh --crds-only --wait
#
# Default: recover main umbrella, then CRDs umbrella (same release names as helm-apply.sh).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_CLUSTER="${HELM_CLUSTER:-local}"
HELM_RELEASE="${HELM_RELEASE:-}"
HELM_CRDS_RELEASE="${HELM_CRDS_RELEASE:-}"
HELM_CRDS_NAMESPACE="${HELM_CRDS_NAMESPACE:-kube-system}"
HELM_NAMESPACE="${HELM_NAMESPACE:-workbench-platform}"
HELM_SKIP_CONTEXT_SWITCH="${HELM_SKIP_CONTEXT_SWITCH:-0}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-}"
AUTO_APPROVE=false
HELM_WAIT=false
RECOVER_MAIN=true
RECOVER_CRDS=true
FORCE=false

list_helm_clusters() {
  find "${ROOT}/devops/clusters" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

usage() {
  cat <<'EOF'
Recover Workbench Helm releases after a failed or pending upgrade.

For each targeted release: if status is failed or pending-*, roll back to the last
revision that reached "deployed"; otherwise roll back to the previous revision.
If rollback is not possible (e.g. only one failed revision), uninstall the release.

Then re-run: ./scripts/helm-apply.sh

Usage:
  ./scripts/helm-recover.sh [options]

Options:
  --cluster <name>        Cluster overlay name (default: local)
  --context <name>        kubectl context (overrides cluster.conf)
  --skip-context-switch   Do not change kubectl context
  --main-only             Recover only workbench-umbrella-<cluster>
  --crds-only             Recover only workbench-crds-umbrella-<cluster>
  --force                 Recover even when status is already "deployed"
  --wait                  Pass --wait to helm rollback / uninstall
  -y, --auto-approve      Skip confirmation prompts
  -h, --help              Show this help

Environment:
  HELM_CLUSTER            Same as --cluster (default: local)
  HELM_RELEASE            Main release (default: workbench-umbrella-<cluster>)
  HELM_CRDS_RELEASE       CRDs release (default: workbench-crds-umbrella-<cluster>)
  HELM_CRDS_NAMESPACE     CRDs release namespace (default: kube-system)
  HELM_NAMESPACE          Main release namespace (default: workbench-platform)
  KUBECTL_CONTEXT         Explicit kubectl context

Requires: helm, jq
EOF
  echo ""
  echo "Available clusters:"
  list_helm_clusters | sed 's/^/  /'
}

require_helm() {
  if ! command -v helm >/dev/null 2>&1; then
    echo "helm is not installed or not on PATH." >&2
    exit 1
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for helm-recover.sh." >&2
    exit 1
  fi
}

confirm_recover() {
  local release="$1"
  local namespace="$2"
  local reply
  read -r -p "Recover release '${release}' in namespace '${namespace}'? [y/N] " reply
  reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

helm_release_status() {
  helm status "$1" -n "$2" -o json 2>/dev/null | jq -r '.info.status // empty'
}

helm_release_version() {
  helm status "$1" -n "$2" -o json 2>/dev/null | jq -r '.version // empty'
}

helm_last_deployed_revision() {
  helm history "$1" -n "$2" -o json 2>/dev/null | jq -r '
    ([.[] | select(.status == "deployed")] | last | .revision) // empty
  '
}

helm_history_count() {
  helm history "$1" -n "$2" -o json 2>/dev/null | jq 'length'
}

status_needs_recover() {
  case "$1" in
    failed|pending-install|pending-upgrade|pending-rollback|uninstalling|unknown)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

recover_release() {
  local release="$1"
  local namespace="$2"
  local -a wait_args=()
  if [[ "${HELM_WAIT}" == "true" ]]; then
    wait_args=(--wait)
  fi

  if ! helm status "${release}" -n "${namespace}" >/dev/null 2>&1; then
    echo "==> ${release} (namespace ${namespace}): not installed (skip)"
    return 0
  fi

  local status version
  status="$(helm_release_status "${release}" "${namespace}")"
  version="$(helm_release_version "${release}" "${namespace}")"

  echo "==> ${release} (namespace ${namespace}): status=${status}, revision=${version}"
  helm status "${release}" -n "${namespace}" 2>/dev/null | sed -n '1,14p' || true

  if [[ "${status}" == "deployed" && "${FORCE}" != "true" ]]; then
    echo "    OK (deployed). Use --force to recover anyway."
    return 0
  fi

  if [[ "${status}" == "uninstalled" ]]; then
    echo "    Already uninstalled (skip)."
    return 0
  fi

  if [[ "${FORCE}" != "true" ]] && ! status_needs_recover "${status}"; then
    echo "    Status '${status}' is not a failed/pending state (skip). Use --force to recover anyway."
    return 0
  fi

  if [[ "${AUTO_APPROVE}" != "true" ]]; then
    if ! confirm_recover "${release}" "${namespace}"; then
      echo "    Aborted."
      return 0
    fi
  fi

  local target_rev rolled_back=false
  target_rev="$(helm_last_deployed_revision "${release}" "${namespace}")"

  if [[ -n "${target_rev}" && "${target_rev}" != "${version}" ]]; then
    echo "    Rolling back to last deployed revision ${target_rev}..."
    if ((${#wait_args[@]} > 0)); then
      if helm rollback "${release}" "${target_rev}" -n "${namespace}" "${wait_args[@]}"; then
        rolled_back=true
      fi
    elif helm rollback "${release}" "${target_rev}" -n "${namespace}"; then
      rolled_back=true
    fi
    if [[ "${rolled_back}" == "true" ]]; then
      echo "    Rollback to revision ${target_rev} succeeded."
    else
      echo "    Rollback to revision ${target_rev} failed." >&2
    fi
  fi

  if [[ "${rolled_back}" != "true" ]]; then
    local count
    count="$(helm_history_count "${release}" "${namespace}")"
    if [[ "${count}" -gt 1 ]]; then
      echo "    Trying rollback to previous revision..."
      if ((${#wait_args[@]} > 0)); then
        helm rollback "${release}" -n "${namespace}" "${wait_args[@]}" && rolled_back=true
      else
        helm rollback "${release}" -n "${namespace}" && rolled_back=true
      fi
      if [[ "${rolled_back}" == "true" ]]; then
        echo "    Rollback succeeded."
      else
        echo "    Rollback to previous revision failed." >&2
      fi
    fi
  fi

  if [[ "${rolled_back}" != "true" ]]; then
    echo "    No rollback target; uninstalling release..."
    if ((${#wait_args[@]} > 0)); then
      helm uninstall "${release}" -n "${namespace}" "${wait_args[@]}"
    else
      helm uninstall "${release}" -n "${namespace}"
    fi
    echo "    Uninstalled. Run ./scripts/helm-apply.sh to install again."
  fi
}

recover_crds_release() {
  if helm status "${CRDS_RELEASE}" -n "${HELM_CRDS_NAMESPACE}" >/dev/null 2>&1; then
    recover_release "${CRDS_RELEASE}" "${HELM_CRDS_NAMESPACE}"
    return
  fi
  if helm status "${CRDS_RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "CRDs release found in legacy namespace '${NAMESPACE}'."
    recover_release "${CRDS_RELEASE}" "${NAMESPACE}"
    return
  fi
  echo "==> ${CRDS_RELEASE}: not found in ${HELM_CRDS_NAMESPACE} or ${NAMESPACE} (skip)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "Missing value for --cluster" >&2; exit 1; }
      HELM_CLUSTER="$2"
      shift 2
      ;;
    --context)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "Missing value for --context" >&2; exit 1; }
      KUBECTL_CONTEXT="$2"
      shift 2
      ;;
    --skip-context-switch)
      HELM_SKIP_CONTEXT_SWITCH=1
      shift
      ;;
    --main-only)
      RECOVER_MAIN=true
      RECOVER_CRDS=false
      shift
      ;;
    --crds-only)
      RECOVER_MAIN=false
      RECOVER_CRDS=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --wait)
      HELM_WAIT=true
      shift
      ;;
    -y|--auto-approve)
      AUTO_APPROVE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

VALUES_CLUSTER="${ROOT}/devops/clusters/${HELM_CLUSTER}/global-values.yaml"
RELEASE="${HELM_RELEASE:-workbench-umbrella-${HELM_CLUSTER}}"
CRDS_RELEASE="${HELM_CRDS_RELEASE:-workbench-crds-umbrella-${HELM_CLUSTER}}"
NAMESPACE="${HELM_NAMESPACE}"

if [[ ! -f "${VALUES_CLUSTER}" ]]; then
  echo "Unknown cluster: ${HELM_CLUSTER}" >&2
  list_helm_clusters | sed 's/^/  /' >&2
  exit 1
fi

require_helm
require_jq

if [[ "${HELM_SKIP_CONTEXT_SWITCH}" != "1" ]]; then
  # shellcheck source=scripts/lib/helm-kubectl-context.sh
  source "${ROOT}/scripts/lib/helm-kubectl-context.sh"
  helm_kubectl_use_context "${HELM_CLUSTER}"
fi

if [[ "${RECOVER_MAIN}" == "true" ]]; then
  recover_release "${RELEASE}" "${NAMESPACE}"
fi

if [[ "${RECOVER_CRDS}" == "true" ]]; then
  recover_crds_release
fi

echo "Done. Re-run ./scripts/helm-apply.sh when ready."
