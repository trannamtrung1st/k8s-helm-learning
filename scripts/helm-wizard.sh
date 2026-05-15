#!/bin/bash
set -euo pipefail

# Interactive menu for common Helm workflows. For each action you enter flags
# and operands; the script prints a copy/paste-safe command line, then runs it
# (uninstall/rollback ask before running [y/N]). After output you press Enter to
# clear the screen and return to the menu.
#
# Path prompts use bash readline (read -e): Tab completes file and directory
# names like in an interactive shell (when stdin is a terminal).
#
# Requires: helm on PATH, kubectl context set when using cluster-scoped actions.
#
# Run from repository root or anywhere:
#   ./scripts/helm-wizard.sh

require_helm() {
  if ! command -v helm >/dev/null 2>&1; then
    echo "helm is not installed or not on PATH."
    exit 1
  fi
}

prompt_nonempty() {
  local prompt="$1"
  local default="${2:-}"
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

prompt_optional() {
  local prompt="$1"
  local out
  read -r -p "${prompt} (leave empty to skip): " out
  echo "${out}"
}

# Same as prompt_* but with read -e so readline enables Tab completion on paths.
prompt_nonempty_path() {
  local prompt="$1"
  local default="${2:-}"
  local out
  if [[ -n "${default}" ]]; then
    read -e -r -p "${prompt} [${default}]: " out
    echo "${out:-${default}}"
  else
    while true; do
      read -e -r -p "${prompt}: " out
      if [[ -n "${out}" ]]; then
        echo "${out}"
        return
      fi
      echo "Value required."
    done
  fi
}

prompt_optional_path() {
  local prompt="$1"
  local out
  read -e -r -p "${prompt} (leave empty to skip): " out
  echo "${out}"
}

prompt_yes_no_default_yes() {
  local reply
  read -r -p "${1} [Y/n]: " reply
  reply="$(echo "${reply:-y}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" != "n" && "${reply}" != "no" ]]
}

prompt_yes_no_default_no() {
  local reply
  read -r -p "${1} [y/N]: " reply
  reply="$(echo "${reply}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

clear_screen_session() {
  if command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[3J\033[H\033[2J'
  fi
}

# After a command (or skip), let the user read output, then clear for the next menu.
pause_and_refresh() {
  echo ""
  read -r -p "Press Enter to return to the menu… " _ || true
  clear_screen_session
}

print_final_command() {
  echo ""
  echo "=== Command (copy/paste) ==="
  printf '%q' "$1"
  shift
  if [[ $# -gt 0 ]]; then
    printf ' %q' "$@"
  fi
  echo
  echo "============================"
  echo ""
}

# Usage: finalize_cmd auto|confirm_no -- cmd...
# Prints a shell-quoted copy/paste line, then runs it. With confirm_no (uninstall,
# rollback), prompts before running [y/N].
finalize_cmd() {
  local mode="$1"
  shift
  if [[ "${1}" != "--" ]]; then
    echo "Internal error: expected -- before command."
    exit 1
  fi
  shift
  print_final_command "$@"
  if [[ "${mode}" == "confirm_no" ]]; then
    if ! prompt_yes_no_default_no "Run this command now?"; then
      echo "Skipped execution."
      pause_and_refresh
      return 0
    fi
  fi
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    echo "" >&2
    echo "(command exited with status ${rc})" >&2
  fi
  pause_and_refresh
}

# Reads lines into global WIZ_VALS_LINES as separate args (each non-empty line is
# one --values / -f path). Helm merges multiple files in order; later keys win.
WIZ_VALS_LINES=()

read_values_files_into_array() {
  WIZ_VALS_LINES=()
  local f
  echo "Optional values files: enter one path per line (each becomes -f/--values)."
  echo "Helm merges in order (later overrides earlier). Empty line when done."
  while true; do
    read -e -r -p "Values file path (empty = done): " f
    [[ -z "${f}" ]] && break
    WIZ_VALS_LINES+=(-f "${f}")
  done
}

# Helper: optional -n namespace from user
read_namespace_optional() {
  prompt_optional "Kubernetes namespace (-n)"
}

read_history_max() {
  prompt_nonempty "Revision history limit (--history-max)" "5"
}

wiz_helm_version() {
  require_helm
  local -a cmd=(helm version)
  if prompt_yes_no_default_no "Add --short?"; then
    cmd+=(--short)
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_repo_add() {
  require_helm
  local name url
  name="$(prompt_nonempty "Repo name (e.g. bitnami)")"
  url="$(prompt_nonempty "Repo URL (https://...)")"
  local -a cmd=(helm repo add "${name}" "${url}")
  if prompt_yes_no_default_no "Add --force-update?"; then
    cmd+=(--force-update)
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_repo_update() {
  require_helm
  local r
  r="$(prompt_optional "Single repo name to update (empty = helm repo update all)")"
  local -a cmd=(helm repo update)
  if [[ -n "${r}" ]]; then
    cmd+=("${r}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_repo_list() {
  require_helm
  finalize_cmd auto -- helm repo list
}

wiz_search_repo() {
  require_helm
  local kw
  kw="$(prompt_nonempty "Search keyword")"
  local -a cmd=(helm search repo "${kw}")
  if prompt_yes_no_default_no "Add --versions (all versions)?"; then
    cmd+=(--versions)
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_install() {
  require_helm
  local rel chart ns history_max
  rel="$(prompt_nonempty "Release name")"
  chart="$(prompt_nonempty_path "Chart (repo/chart or local path)")"
  ns="$(read_namespace_optional)"
  history_max="$(read_history_max)"
  read_values_files_into_array
  local -a cmd=(helm install "${rel}" "${chart}")
  if prompt_yes_no_default_yes "Use server-side apply (--server-side=true)?"; then
    cmd+=(--server-side=true)
  else
    cmd+=(--server-side=false)
  fi
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  if prompt_yes_no_default_no "Add --create-namespace?"; then
    cmd+=(--create-namespace)
  fi
  if [[ ${#WIZ_VALS_LINES[@]} -gt 0 ]]; then
    cmd+=("${WIZ_VALS_LINES[@]}")
  fi
  cmd+=(--history-max "${history_max}")
  if prompt_yes_no_default_no "Add --dry-run=server (simulate on API, no persist)?"; then
    cmd+=(--dry-run=server)
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_upgrade() {
  require_helm
  local rel chart ns history_max
  rel="$(prompt_nonempty "Release name")"
  chart="$(prompt_nonempty_path "Chart (repo/chart or local path)")"
  ns="$(read_namespace_optional)"
  history_max="$(read_history_max)"
  read_values_files_into_array
  local -a cmd=(helm upgrade "${rel}" "${chart}")
  if prompt_yes_no_default_yes "Use server-side apply (--server-side=true)?"; then
    cmd+=(--server-side=true)
  else
    cmd+=(--server-side=false)
  fi
  if prompt_yes_no_default_no "Add --install (release-if-missing)?"; then
    cmd+=(--install)
  fi
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  if prompt_yes_no_default_no "Add --create-namespace?"; then
    cmd+=(--create-namespace)
  fi
  if [[ ${#WIZ_VALS_LINES[@]} -gt 0 ]]; then
    cmd+=("${WIZ_VALS_LINES[@]}")
  fi
  cmd+=(--history-max "${history_max}")
  if prompt_yes_no_default_no "Add --dry-run=server (simulate on API, no persist)?"; then
    cmd+=(--dry-run=server)
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_uninstall() {
  require_helm
  local rel ns
  rel="$(prompt_nonempty "Release name to uninstall")"
  ns="$(read_namespace_optional)"
  local -a cmd=(helm uninstall "${rel}")
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  if prompt_yes_no_default_yes "Add --wait?"; then
    cmd+=(--wait)
  fi
  if prompt_yes_no_default_no "Add --keep-history?"; then
    cmd+=(--keep-history)
  fi
  echo "This removes the release from the cluster."
  finalize_cmd confirm_no -- "${cmd[@]}"
}

wiz_list() {
  require_helm
  local -a cmd=(helm list)
  if prompt_yes_no_default_no "List releases in all namespaces (-A)?"; then
    cmd+=(-A)
  else
    local ns
    ns="$(read_namespace_optional)"
    if [[ -n "${ns}" ]]; then
      cmd+=(-n "${ns}")
    fi
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_status() {
  require_helm
  local rel ns
  rel="$(prompt_nonempty "Release name")"
  ns="$(read_namespace_optional)"
  local -a cmd=(helm status "${rel}")
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_history() {
  require_helm
  local rel ns max
  rel="$(prompt_nonempty "Release name")"
  ns="$(read_namespace_optional)"
  max="$(prompt_optional "Max revisions (--max), empty for default")"
  local -a cmd=(helm history "${rel}")
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  if [[ -n "${max}" ]]; then
    cmd+=(--max "${max}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_rollback() {
  require_helm
  local rel rev ns
  rel="$(prompt_nonempty "Release name")"
  rev="$(prompt_nonempty "Revision number to roll back to")"
  ns="$(read_namespace_optional)"
  local -a cmd=(helm rollback "${rel}" "${rev}")
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  if prompt_yes_no_default_yes "Add --wait?"; then
    cmd+=(--wait)
  fi
  if prompt_yes_no_default_no "Add --dry-run=server (simulate on API, no persist)?"; then
    cmd+=(--dry-run=server)
  fi
  echo "Rollback changes live resources for this release."
  finalize_cmd confirm_no -- "${cmd[@]}"
}

wiz_get() {
  require_helm
  echo "What to get?"
  echo "  1) values"
  echo "  2) manifest"
  echo "  3) notes"
  echo "  4) all"
  local sub rel ns rev
  read -r -p "Choose [1-4]: " sub
  case "${sub}" in
    1) sub="values" ;;
    2) sub="manifest" ;;
    3) sub="notes" ;;
    4) sub="all" ;;
    *)
      echo "Invalid choice."
      return
      ;;
  esac
  rel="$(prompt_nonempty "Release name")"
  ns="$(read_namespace_optional)"
  rev="$(prompt_optional "Revision (--revision), empty for latest")"
  local -a cmd=(helm get "${sub}" "${rel}")
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  if [[ -n "${rev}" ]]; then
    cmd+=(--revision "${rev}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_template() {
  require_helm
  local rel chart ns
  rel="$(prompt_nonempty "Release name (logical name for template)")"
  chart="$(prompt_nonempty_path "Chart (repo/chart or local path)")"
  ns="$(read_namespace_optional)"
  read_values_files_into_array
  local -a cmd=(helm template "${rel}" "${chart}")
  if [[ -n "${ns}" ]]; then
    cmd+=(-n "${ns}")
  fi
  if [[ ${#WIZ_VALS_LINES[@]} -gt 0 ]]; then
    cmd+=("${WIZ_VALS_LINES[@]}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_lint() {
  require_helm
  local path
  path="$(prompt_nonempty_path "Chart directory or packaged chart path")"
  read_values_files_into_array
  local -a cmd=(helm lint "${path}")
  if prompt_yes_no_default_no "Add --strict?"; then
    cmd+=(--strict)
  fi
  if [[ ${#WIZ_VALS_LINES[@]} -gt 0 ]]; then
    cmd+=("${WIZ_VALS_LINES[@]}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_show() {
  require_helm
  echo "Show subcommand?"
  echo "  1) chart"
  echo "  2) values"
  echo "  3) readme"
  local sub chart ver
  read -r -p "Choose [1-3]: " sub
  case "${sub}" in
    1) sub="chart" ;;
    2) sub="values" ;;
    3) sub="readme" ;;
    *)
      echo "Invalid choice."
      return
      ;;
  esac
  chart="$(prompt_nonempty_path "Chart (repo/chart or URI)")"
  ver="$(prompt_optional "Chart version (--version), empty to skip")"
  local -a cmd=(helm show "${sub}" "${chart}")
  if [[ -n "${ver}" ]]; then
    cmd+=(--version "${ver}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_pull() {
  require_helm
  local chart ver dest
  chart="$(prompt_nonempty_path "Chart (repo/chart or URI)")"
  ver="$(prompt_optional "Chart version (--version), empty to skip")"
  dest="$(prompt_optional_path "Destination directory (-d), empty to skip")"
  local -a cmd=(helm pull "${chart}")
  if [[ -n "${ver}" ]]; then
    cmd+=(--version "${ver}")
  fi
  if [[ -n "${dest}" ]]; then
    cmd+=(-d "${dest}")
  fi
  if prompt_yes_no_default_no "Add --untar?"; then
    cmd+=(--untar)
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_dependency() {
  require_helm
  echo "Dependency action?"
  echo "  1) helm dependency update CHART_DIR"
  echo "  2) helm dependency build CHART_DIR"
  local c path
  read -r -p "Choose [1-2]: " c
  path="$(prompt_nonempty_path "Chart directory (containing Chart.yaml)")"
  local -a cmd
  case "${c}" in
    1) cmd=(helm dependency update "${path}") ;;
    2) cmd=(helm dependency build "${path}") ;;
    *)
      echo "Invalid choice."
      return
      ;;
  esac
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_create_chart() {
  require_helm
  local path starter
  path="$(prompt_nonempty_path "Chart path to create (e.g. devops/infra/my-chart)")"
  if [[ -e "${path}" ]]; then
    echo "That path already exists. helm create will add/overwrite scaffold files where needed."
    if ! prompt_yes_no_default_no "Continue?"; then
      echo "Aborted."
      pause_and_refresh
      return 0
    fi
  fi
  starter="$(prompt_optional_path "Starter for -p (--starter): built-in name or absolute path")"
  local -a cmd=(helm create "${path}")
  if [[ -n "${starter}" ]]; then
    cmd+=(-p "${starter}")
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

wiz_package_chart() {
  require_helm
  local path dest ver appver
  path="$(prompt_nonempty_path "Chart directory (contains Chart.yaml)")"
  dest="$(prompt_optional_path "Package output directory (-d), empty for current directory")"
  ver="$(prompt_optional "Override chart version (--version), empty to use Chart.yaml")"
  appver="$(prompt_optional "Override appVersion (--app-version), empty to skip")"
  local -a cmd=(helm package "${path}")
  if [[ -n "${dest}" ]]; then
    cmd+=(-d "${dest}")
  fi
  if [[ -n "${ver}" ]]; then
    cmd+=(--version "${ver}")
  fi
  if [[ -n "${appver}" ]]; then
    cmd+=(--app-version "${appver}")
  fi
  if prompt_yes_no_default_no "Update dependencies before package (-u)?"; then
    cmd+=(-u)
  fi
  finalize_cmd auto -- "${cmd[@]}"
}

show_help() {
  cat <<EOF
Interactive Helm command wizard: prompts for operands, prints a shell-quoted
command you can copy, then runs it. Uninstall and rollback ask before running
[y/N]. After each run (or skip), press Enter to clear the screen and return to
the menu.

Install and upgrade prompt for --history-max (default 5). Install, upgrade,
template, and lint can prompt for multiple values files (-f); each path is
merged in the order you enter (later overrides earlier).

  $0              # interactive menu
  $0 --help       # this text

Requires: helm
EOF
}

main_menu() {
  require_helm
  clear_screen_session
  while true; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Helm command wizard"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if command -v kubectl >/dev/null 2>&1; then
      echo "  kubectl context: $(kubectl config current-context 2>/dev/null || echo '(unknown)')"
    else
      echo "  kubectl: (not installed — context unknown)"
    fi
    echo ""
    echo "  1)  helm version           — show Helm client and Kubernetes API versions"
    echo "  2)  helm repo add          — register a chart repository by name and URL"
    echo "  3)  helm repo update       — fetch latest index for one or all repos"
    echo "  4)  helm repo list         — list configured chart repositories"
    echo "  5)  helm search repo        — search charts in added repositories"
    echo "  6)  helm install            — install a release from a chart"
    echo "  7)  helm upgrade             — upgrade an existing release (optional --install)"
    echo "  8)  helm uninstall          — remove a release from the cluster"
    echo "  9)  helm list                — list releases (optionally all namespaces)"
    echo "  10) helm status              — show status of a named release"
    echo "  11) helm history             — list revision history for a release"
    echo "  12) helm rollback            — roll a release back to a prior revision"
    echo "  13) helm get                 — print values, manifest, notes, or all"
    echo "  14) helm template            — render chart templates locally (no cluster apply)"
    echo "  15) helm lint                — run checks on a chart (optional multiple -f values files)"
    echo "  16) helm show                — show chart metadata, default values, or readme"
    echo "  17) helm pull                — download a chart package from a repo or URI"
    echo "  18) helm dependency          — update or vendor subchart dependencies"
    echo "  19) helm create              — scaffold Chart.yaml, templates/, values.yaml, …"
    echo "  20) helm package             — build a versioned .tgz from a chart directory"
    echo "  0)  Exit"
    echo ""
    local choice
    if ! read -r -p "Choose [0-20]: " choice; then
      echo ""
      echo "EOF — exiting."
      exit 0
    fi
    case "${choice}" in
      1) wiz_helm_version ;;
      2) wiz_repo_add ;;
      3) wiz_repo_update ;;
      4) wiz_repo_list ;;
      5) wiz_search_repo ;;
      6) wiz_install ;;
      7) wiz_upgrade ;;
      8) wiz_uninstall ;;
      9) wiz_list ;;
      10) wiz_status ;;
      11) wiz_history ;;
      12) wiz_rollback ;;
      13) wiz_get ;;
      14) wiz_template ;;
      15) wiz_lint ;;
      16) wiz_show ;;
      17) wiz_pull ;;
      18) wiz_dependency ;;
      19) wiz_create_chart ;;
      20) wiz_package_chart ;;
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
  "")
    main_menu
    ;;
  *)
    echo "Unknown argument: $1"
    show_help
    exit 1
    ;;
esac
