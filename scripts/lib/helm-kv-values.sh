#!/bin/bash
# shellcheck shell=bash
# Build a Helm values file (JSON) from Azure Key Vault secrets for AKS installs.
#
# Sourced by helm-apply.sh when --cluster aks (unless --skip-kv-secrets).
#
# Environment:
#   KEY_VAULT_NAME  Vault name (from terraform output key_vault_name)

helm_kv_resolve_vault_name() {
  if [[ -z "${KEY_VAULT_NAME:-}" ]]; then
    # shellcheck source=scripts/lib/terraform-outputs.sh
    source "${ROOT}/scripts/lib/terraform-outputs.sh"
    terraform_outputs_apply_env
  fi
  : "${KEY_VAULT_NAME:?KEY_VAULT_NAME not set. Run terraform apply or export KEY_VAULT_NAME.}"
}

helm_kv_require_tools() {
  local cmd
  for cmd in az jq; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "helm-kv-values: '${cmd}' is required for AKS Key Vault values." >&2
      exit 1
    fi
  done
}

helm_kv_fetch_secret() {
  local secret_name="$1"
  local value
  if ! value="$(az keyvault secret show \
    --vault-name "${KEY_VAULT_NAME}" \
    --name "${secret_name}" \
    --query value -o tsv 2>/dev/null)"; then
    echo "Failed to read Key Vault secret '${secret_name}' from '${KEY_VAULT_NAME}'." >&2
    echo "Ensure 'az login' and Key Vault Secrets User (or Officer) on the vault." >&2
    return 1
  fi
  if [[ -z "${value}" ]]; then
    echo "Key Vault secret '${secret_name}' is empty." >&2
    return 1
  fi
  printf '%s' "${value}"
}

# Usage: helm_kv_values_write <output.json>
helm_kv_values_write() {
  local out_file="$1"
  helm_kv_resolve_vault_name
  helm_kv_require_tools

  echo "==> Reading Helm secrets from Key Vault: ${KEY_VAULT_NAME}" >&2

  local pg_conn pg_user pg_pass pg_db rmq_uri redis_conn redis_user redis_pass
  pg_conn="$(helm_kv_fetch_secret workbench-postgres-connection-string)"
  pg_user="$(helm_kv_fetch_secret workbench-postgres-user)"
  pg_pass="$(helm_kv_fetch_secret workbench-postgres-password)"
  pg_db="$(helm_kv_fetch_secret workbench-postgres-database)"
  rmq_uri="$(helm_kv_fetch_secret workbench-rabbitmq-uri)"
  redis_conn="$(helm_kv_fetch_secret workbench-redis-connection-string)"
  redis_user="$(helm_kv_fetch_secret workbench-redis-user)"
  redis_pass="$(helm_kv_fetch_secret workbench-redis-password)"

  jq -n \
    --arg pg_conn "${pg_conn}" \
    --arg pg_user "${pg_user}" \
    --arg pg_pass "${pg_pass}" \
    --arg pg_db "${pg_db}" \
    --arg rmq_uri "${rmq_uri}" \
    --arg redis_conn "${redis_conn}" \
    --arg redis_user "${redis_user}" \
    --arg redis_pass "${redis_pass}" \
    '{
      global: {
        workbenchPostgres: {
          connectionString: $pg_conn,
          user: $pg_user,
          password: $pg_pass,
          database: $pg_db
        },
        workbenchRabbitMq: {
          uri: $rmq_uri
        },
        workbenchRedis: {
          connectionString: $redis_conn,
          user: $redis_user,
          password: $redis_pass
        }
      }
    }' >"${out_file}"
}
