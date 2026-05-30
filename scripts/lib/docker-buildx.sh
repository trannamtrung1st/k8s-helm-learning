# shellcheck shell=bash
# Multi-arch docker buildx helpers for Workbench app images.
#
# Environment:
#   WORKBENCH_REGISTRY   (default: workbenchacr77.azurecr.io)
#   WORKBENCH_IMAGE_TAG  (default: 1.0.0-rc1)
#   WORKBENCH_PLATFORMS  (default: linux/amd64,linux/arm64)
#   WORKBENCH_BUILDX_BUILDER (default: workbench-multiarch)

: "${WORKBENCH_REGISTRY:=workbenchacr77.azurecr.io}"
: "${WORKBENCH_IMAGE_TAG:=1.0.0-rc1}"
: "${WORKBENCH_PLATFORMS:=linux/amd64,linux/arm64}"
: "${WORKBENCH_BUILDX_BUILDER:=workbench-multiarch}"

workbench_buildx_host_platform() {
  case "$(uname -m)" in
    aarch64 | arm64) echo linux/arm64 ;;
    x86_64 | amd64) echo linux/amd64 ;;
    *) echo linux/amd64 ;;
  esac
}

# Print app image refs (one per line). include_jobs=1 adds workbench-jobs (compose profile: jobs).
workbench_app_images() {
  local include_jobs="${1:-1}"
  local tag="${WORKBENCH_IMAGE_TAG}"
  local -a images=(
    "${WORKBENCH_REGISTRY}/workbench-api:${tag}"
    "${WORKBENCH_REGISTRY}/workbench-worker:${tag}"
    "${WORKBENCH_REGISTRY}/workbench-app:${tag}"
    "${WORKBENCH_REGISTRY}/workbench-local-gateway:${tag}"
  )
  if [[ "${include_jobs}" == "1" ]]; then
    images+=("${WORKBENCH_REGISTRY}/workbench-jobs:${tag}")
  fi
  printf '%s\n' "${images[@]}"
}

workbench_buildx_ensure_builder() {
  if ! docker buildx version >/dev/null 2>&1; then
    echo "docker buildx is required for multi-arch builds." >&2
    return 1
  fi
  if docker buildx inspect "${WORKBENCH_BUILDX_BUILDER}" >/dev/null 2>&1; then
    docker buildx use "${WORKBENCH_BUILDX_BUILDER}" >/dev/null
  else
    docker buildx create --name "${WORKBENCH_BUILDX_BUILDER}" --driver docker-container --use
  fi
}

# Args: image_tag context_dir dockerfile_relative_to_context
workbench_buildx_build_one() {
  local image="$1"
  local context="$2"
  local dockerfile="$3"
  local mode="${4:-load}"

  local -a cmd=(buildx build
    --file "${context}/${dockerfile}"
    --tag "${image}"
  )

  case "${mode}" in
    load)
      cmd+=(--platform "$(workbench_buildx_host_platform)" --load)
      ;;
    push)
      cmd+=(--platform "${WORKBENCH_PLATFORMS}" --push)
      ;;
    *)
      echo "workbench_buildx_build_one: unknown mode ${mode} (use load or push)" >&2
      return 1
      ;;
  esac

  cmd+=("${context}")
  echo "==> docker ${cmd[*]}"
  docker "${cmd[@]}"
}

# Build all app images. mode=load (local docker) or push (multi-arch manifest to registry).
workbench_buildx_build_apps() {
  local root="$1"
  local include_jobs="${2:-1}"
  local mode="${3:-load}"

  workbench_buildx_ensure_builder || return 1

  local tag="${WORKBENCH_IMAGE_TAG}"
  local -a specs=(
    "${WORKBENCH_REGISTRY}/workbench-api:${tag}|${root}/src|Workbench.Api/Dockerfile"
    "${WORKBENCH_REGISTRY}/workbench-worker:${tag}|${root}/src|Workbench.Worker/Dockerfile"
    "${WORKBENCH_REGISTRY}/workbench-app:${tag}|${root}/src/workbench-app|Dockerfile"
    "${WORKBENCH_REGISTRY}/workbench-local-gateway:${tag}|${root}/src|Workbench.LocalGateway/Dockerfile"
  )
  if [[ "${include_jobs}" == "1" ]]; then
    specs+=("${WORKBENCH_REGISTRY}/workbench-jobs:${tag}|${root}/src|Workbench.Jobs/Dockerfile")
  fi

  local spec image context dockerfile
  for spec in "${specs[@]}"; do
    IFS='|' read -r image context dockerfile <<<"${spec}"
    workbench_buildx_build_one "${image}" "${context}" "${dockerfile}" "${mode}" || return 1
  done

  if [[ "${mode}" == "load" ]]; then
    echo "Loaded host platform $(workbench_buildx_host_platform) into local Docker (tag: ${tag})."
    echo "Push multi-arch manifest: ./scripts/compose-wizard.sh push"
  else
    echo "Pushed multi-arch manifest (${WORKBENCH_PLATFORMS}) to ${WORKBENCH_REGISTRY}."
  fi
}
