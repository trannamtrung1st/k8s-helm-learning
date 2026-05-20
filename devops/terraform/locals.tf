resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  name_suffix = random_string.suffix.result

  # Key Vault names: 3–24 chars, alphanumeric and hyphens.
  key_vault_name = substr("workbench-kv-${local.name_suffix}", 0, 24)
}
