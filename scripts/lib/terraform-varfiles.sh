#!/bin/bash
# shellcheck shell=bash
# Build -var-file arguments for Terraform scripts.
#
# After terraform_varfiles_build, use "${TERRAFORM_VARFILES[@]}".
#
# Environment:
#   VAR_FILE            Primary tfvars (default: vars/prod.tfvars)
#   SECRETS_VAR_FILE    Key Vault / workbench_secrets tfvars (default: vars/secrets.tfvars)
#   USE_SECRETS_TFVARS  auto (default): append secrets file when it exists on disk
#                       true: require secrets file
#                       false: never append secrets file

TERRAFORM_VARFILES=()

terraform_varfiles_build() {
  local tf_dir="$1"
  local var_file="${VAR_FILE:-vars/prod.tfvars}"
  local secrets_file="${SECRETS_VAR_FILE:-vars/secrets.tfvars}"

  TERRAFORM_VARFILES=(-var-file "${var_file}")

  case "${USE_SECRETS_TFVARS:-auto}" in
    false | 0 | no)
      return 0
      ;;
    true | 1 | yes)
      if [[ ! -f "${tf_dir}/${secrets_file}" ]]; then
        echo "terraform-varfiles: ${tf_dir}/${secrets_file} not found (USE_SECRETS_TFVARS=true)" >&2
        exit 1
      fi
      TERRAFORM_VARFILES+=(-var-file "${secrets_file}")
      ;;
    auto | *)
      if [[ -f "${tf_dir}/${secrets_file}" ]]; then
        TERRAFORM_VARFILES+=(-var-file "${secrets_file}")
      fi
      ;;
  esac
}

# Comma-separated var file paths (for log lines).
terraform_varfiles_label() {
  local tf_dir="$1"
  terraform_varfiles_build "${tf_dir}"
  local files=()
  local i
  for ((i = 1; i < ${#TERRAFORM_VARFILES[@]}; i += 2)); do
    files+=("${TERRAFORM_VARFILES[$i]}")
  done
  local IFS=', '
  echo "${files[*]}"
}
