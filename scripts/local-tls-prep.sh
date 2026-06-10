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
#   3) Write Helm values overlay for workbench-local-ca-secret
#
# Domain certificates are handled separately (e.g. cert-manager).
# Requires mkcert on PATH (e.g. brew install mkcert).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_CA_VALUES="${ROOT}/devops/clusters/local/local-ca.values.yaml"
DOMAIN="${MKCERT_DOMAIN:-k8slearning.com}"
HOSTS_IP="${MKCERT_HOSTS_IP:-127.0.0.1}"
ADD_HOSTS="true"

usage() {
  cat <<EOF
Usage: $0 [options]

Add a local hostname to /etc/hosts, install mkcert local CA, and write Helm values for workbench-local-ca-secret.

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

write_local_ca_values() {
  local caroot crt_file key_file

  caroot="$(mkcert -CAROOT)"
  crt_file="${caroot}/rootCA.pem"
  key_file="${caroot}/rootCA-key.pem"

  if [[ ! -f "${crt_file}" || ! -f "${key_file}" ]]; then
    echo "mkcert CA files not found under ${caroot}" >&2
    exit 1
  fi

  echo "==> Writing ${LOCAL_CA_VALUES}"
  {
    echo "workbench-local-ca-secret:"
    echo "  enabled: true"
    echo "  tlsCrt: |"
    sed 's/^/    /' "${crt_file}"
    echo "  tlsKey: |"
    sed 's/^/    /' "${key_file}"
  } > "${LOCAL_CA_VALUES}"
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

write_local_ca_values

echo "Done."
