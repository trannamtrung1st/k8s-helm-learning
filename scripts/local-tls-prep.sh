#!/bin/bash
set -euo pipefail

# Local dev TLS prep: /etc/hosts + mkcert local CA.
# Run from repository root.
#
#   ./scripts/local-tls-prep.sh
#   ./scripts/local-tls-prep.sh --domain app.localtest.me
#   ./scripts/local-tls-prep.sh --skip-hosts
#
# Steps:
#   1) Add hostname to /etc/hosts (on by default)
#   2) Install mkcert local CA (trusted by macOS / browsers)
#
# Domain certificates are handled separately (e.g. cert-manager).
# Requires mkcert on PATH (e.g. brew install mkcert).

DOMAIN="${MKCERT_DOMAIN:-k8slearning.com}"
HOSTS_IP="${MKCERT_HOSTS_IP:-127.0.0.1}"
ADD_HOSTS="true"

usage() {
  cat <<EOF
Usage: $0 [options]

Add a local hostname to /etc/hosts and install mkcert local CA.

Options:
  -d, --domain <name>     Hostname for /etc/hosts (default: ${DOMAIN})
  --hosts-ip <ip>         IP for /etc/hosts entry (default: ${HOSTS_IP})
  --skip-hosts            Do not modify /etc/hosts
  -h, --help              Show this help

Environment:
  MKCERT_DOMAIN, MKCERT_HOSTS_IP

Examples:
  $0
  $0 --domain app.localtest.me
  $0 --skip-hosts
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
}

hosts_has_entry() {
  local domain="$1"
  grep -E "^[[:space:]]*[^#[:space:]]+[[:space:]]+.*\\b${domain}\\b" /etc/hosts >/dev/null 2>&1
}

add_hosts_entry() {
  local ip="$1"
  local domain="$2"

  if hosts_has_entry "${domain}"; then
    echo "==> /etc/hosts already contains ${domain} (skip)."
    return 0
  fi

  echo "==> Adding ${ip} ${domain} to /etc/hosts (sudo required)."
  printf '%s %s\n' "${ip}" "${domain}" | sudo tee -a /etc/hosts >/dev/null
  echo "    Added: ${ip} ${domain}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain)
      [[ $# -ge 2 ]] || { echo "Missing value for --domain" >&2; exit 1; }
      DOMAIN="$2"
      shift 2
      ;;
    --hosts-ip)
      [[ $# -ge 2 ]] || { echo "Missing value for --hosts-ip" >&2; exit 1; }
      HOSTS_IP="$2"
      shift 2
      ;;
    --skip-hosts)
      ADD_HOSTS="false"
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

require_cmd mkcert

if [[ "${ADD_HOSTS}" == "true" ]]; then
  add_hosts_entry "${HOSTS_IP}" "${DOMAIN}"
else
  echo "==> Skipping /etc/hosts update (--skip-hosts)."
fi

echo "==> mkcert -install"
mkcert -install

echo "Done."
