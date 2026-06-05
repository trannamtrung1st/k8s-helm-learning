#!/bin/bash
set -euo pipefail

# Install Istio ambient mode (istioctl profile=ambient).
# Run from repository root after kubectl context is set.
#
#   ./scripts/istio-install.sh
#   ./scripts/istio-install.sh --version 1.30.1
#   ./scripts/istio-install.sh --skip-download
#
# See: https://istio.io/latest/docs/ambient/getting-started/

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISTIO_VERSION="${ISTIO_VERSION:-1.30.1}"
ISTIO_HOME="${ISTIO_HOME:-${ROOT}/.cache/istio-${ISTIO_VERSION}}"
SKIP_DOWNLOAD="false"
SKIP_VERIFY="false"

usage() {
  cat <<EOF
Usage: $0 [options]

Download istioctl (if needed) and install Istio with the ambient profile.

Options:
  --version <x.y.z>   Istio release (default: ${ISTIO_VERSION})
  --istio-home <dir>  Install/cache directory (default: .cache/istio-<version>)
  --skip-download     Require istioctl in PATH or ISTIO_HOME/bin (do not curl)
  --skip-verify       Skip post-install pod checks
  -h, --help          Show this help

Environment:
  ISTIO_VERSION, ISTIO_HOME

After install, run ./scripts/gateway-api-install.sh for Kubernetes Gateway API CRDs.
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

istio_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "Unsupported architecture for Istio download: ${arch}" >&2
      exit 1
      ;;
  esac
}

ensure_istioctl() {
  if [[ -x "${ISTIO_HOME}/bin/istioctl" ]]; then
    export PATH="${ISTIO_HOME}/bin:${PATH}"
    return 0
  fi

  if command -v istioctl >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${SKIP_DOWNLOAD}" == "true" ]]; then
    echo "istioctl not found in PATH or ${ISTIO_HOME}/bin (pass without --skip-download to fetch)." >&2
    exit 1
  fi

  require_cmd curl

  local cache_dir="${ROOT}/.cache"
  mkdir -p "${cache_dir}"
  echo "==> Download Istio ${ISTIO_VERSION} to ${cache_dir}"
  (
    cd "${cache_dir}"
    curl -fsSL https://istio.io/downloadIstio | ISTIO_VERSION="${ISTIO_VERSION}" TARGET_ARCH="$(istio_arch)" sh -
  )

  if [[ ! -d "${cache_dir}/istio-${ISTIO_VERSION}" ]]; then
    echo "Expected directory not found after download: ${cache_dir}/istio-${ISTIO_VERSION}" >&2
    exit 1
  fi

  ISTIO_HOME="${cache_dir}/istio-${ISTIO_VERSION}"
  export PATH="${ISTIO_HOME}/bin:${PATH}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "Missing value for --version" >&2; exit 1; }
      ISTIO_VERSION="$2"
      ISTIO_HOME="${ROOT}/.cache/istio-${ISTIO_VERSION}"
      shift 2
      ;;
    --istio-home)
      [[ $# -ge 2 ]] || { echo "Missing value for --istio-home" >&2; exit 1; }
      ISTIO_HOME="$2"
      shift 2
      ;;
    --skip-download)
      SKIP_DOWNLOAD="true"
      shift
      ;;
    --skip-verify)
      SKIP_VERIFY="true"
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

require_cmd kubectl
ensure_istioctl

echo "==> istioctl version"
istioctl version || true

if kubectl get ns istio-system >/dev/null 2>&1 \
  && kubectl get deploy -n istio-system istiod >/dev/null 2>&1; then
  echo "Istio appears installed in istio-system (skip istioctl install)."
else
  echo "==> istioctl install --set profile=ambient --skip-confirmation"
  istioctl install --set profile=ambient --skip-confirmation
fi

if [[ "${SKIP_VERIFY}" != "true" ]]; then
  echo "==> Verify Istio ambient components"
  kubectl get pods -n istio-system
  # DaemonSet has no Ready condition; rollout status waits until scheduled pods are ready.
  kubectl rollout status deployment/istiod -n istio-system --timeout=300s
  kubectl rollout status daemonset/istio-cni-node -n istio-system --timeout=300s
  kubectl rollout status daemonset/ztunnel -n istio-system --timeout=300s
  istioctl version
fi

echo "Done."
