#!/usr/bin/env bash
#
# Interactive (or scripted) Docker Compose helper: multi-arch build → push → up -d.
# Expects Compose file under local/ with ACR image tags (workbenchacr77.azurecr.io/...).
#
# From repo root:
#   ./scripts/compose-wizard.sh              # menu
#   ./scripts/compose-wizard.sh all        # build, push app images, up -d
#   ./scripts/compose-wizard.sh build
#   ./scripts/compose-wizard.sh push
#   ./scripts/compose-wizard.sh up
#   ./scripts/compose-wizard.sh down
#   ./scripts/compose-wizard.sh down --volumes
#
# Environment:
#   COMPOSE_FILE          Full path (default: <repo>/local/docker-compose.yaml)
#   INCLUDE_JOBS          Default 1: include workbench-jobs in build/push
#   WORKBENCH_PLATFORMS   Default linux/amd64,linux/arm64 (push only)
#
# Before push: az acr login --name workbenchacr77   (or docker login to the registry)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/docker-buildx.sh
source "${ROOT}/scripts/lib/docker-buildx.sh"

COMPOSE_FILE="${COMPOSE_FILE:-${ROOT}/local/docker-compose.yaml}"
INCLUDE_JOBS="${INCLUDE_JOBS:-1}"

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is not installed or not on PATH." >&2
    exit 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose v2 ('docker compose') is required." >&2
    exit 1
  fi
}

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
}

compose_file_must_exist() {
  if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "Missing ${COMPOSE_FILE}" >&2
    exit 1
  fi
}

compose_with_profile() {
  (
    cd "${ROOT}"
    if [[ "${INCLUDE_JOBS}" == "1" ]]; then
      docker compose -f "${COMPOSE_FILE}" --profile jobs "$@"
    else
      docker compose -f "${COMPOSE_FILE}" "$@"
    fi
  )
}

compose_build() {
  echo "==> multi-arch buildx (load host arch for local) platforms push=${WORKBENCH_PLATFORMS}"
  workbench_buildx_build_apps "${ROOT}" "${INCLUDE_JOBS}" load
}

compose_push() {
  if ! command -v az >/dev/null 2>&1; then
    echo "Azure CLI ('az') is required for ACR login before push." >&2
    exit 1
  fi
  echo "==> az acr login --name workbenchacr77"
  az acr login --name workbenchacr77
  echo "==> multi-arch buildx push (${WORKBENCH_PLATFORMS})"
  workbench_buildx_build_apps "${ROOT}" "${INCLUDE_JOBS}" push
}

compose_up() {
  echo "==> docker compose up -d ($(basename "${COMPOSE_FILE}"); jobs profile not enabled for up)"
  (
    cd "${ROOT}"
    docker compose -f "${COMPOSE_FILE}" up -d
  )
}

compose_down() {
  echo "==> docker compose down $*"
  (
    cd "${ROOT}"
    docker compose -f "${COMPOSE_FILE}" down "$@"
  )
}

compose_ps() {
  (
    cd "${ROOT}"
    docker compose -f "${COMPOSE_FILE}" ps
  )
}

cmd_all() {
  compose_build
  compose_push
  compose_up
}

interactive_menu() {
  compose_file_must_exist
  echo ""
  echo "=== Docker Compose wizard ($(basename "${COMPOSE_FILE}")) ==="
  echo "  1) build (buildx, load host arch)"
  echo "  2) push (buildx multi-arch → ACR)"
  echo "  3) up -d"
  echo "  4) build + push + up -d"
  echo "  5) down"
  echo "  6) ps"
  echo "  0) quit"
  echo ""
  local choice
  read -r -p "Choice [0-6]: " choice
  case "${choice}" in
    1) compose_build ;;
    2) compose_push ;;
    3) compose_up ;;
    4) cmd_all ;;
    5) compose_down ;;
    6) compose_ps ;;
    0 | "") echo "Bye." ;;
    *) echo "Invalid choice." >&2; exit 1 ;;
  esac
}

main() {
  case "${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
    build)
      require_docker
      compose_file_must_exist
      compose_build
      ;;
    push)
      require_docker
      compose_file_must_exist
      compose_push
      ;;
    up)
      require_docker
      compose_file_must_exist
      compose_up
      ;;
    down)
      require_docker
      compose_file_must_exist
      shift
      compose_down "$@"
      ;;
    ps)
      require_docker
      compose_file_must_exist
      compose_ps
      ;;
    all)
      require_docker
      compose_file_must_exist
      cmd_all
      ;;
    "")
      require_docker
      interactive_menu
      ;;
    *)
      echo "Unknown command: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
