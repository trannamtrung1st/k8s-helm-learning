#!/bin/bash
# Refresh packaged Helm dependencies (charts/*.tgz, Chart.lock) for Workbench:
# charts that depend on workbench-common, then main umbrella.
#
# From repository root:
#   ./scripts/helm-dependency-update.sh
#   ./scripts/helm-dependency-update.sh --skip-refresh
#
# Any extra arguments are forwarded to each `helm dependency update` invocation
# (must be flags Helm accepts globally, e.g. --skip-refresh).
#
# Environment:
#   ROOT is inferred from script location.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UMBRELLA="${ROOT}/devops/umbrellas/workbench-umbrella"

SUBCHARTS=(
  apps/workbench-api
  apps/workbench-worker
  apps/workbench-jobs
  apps/workbench-app
  infra/workbench-postgres
  infra/workbench-rabbitmq
  infra/workbench-redis
)

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is not installed or not on PATH." >&2
  exit 1
fi

for rel in "${SUBCHARTS[@]}"; do
  chart_dir="${ROOT}/devops/${rel}"
  echo "==> helm dependency update \"${chart_dir}\" $*"
  helm dependency update "${chart_dir}" "$@"
done

echo "==> helm dependency update \"${UMBRELLA}\" $*"
helm dependency update "${UMBRELLA}" "$@"
echo "Helm dependency update complete."
