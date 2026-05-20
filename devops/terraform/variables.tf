variable "use_oidc" {
  type        = bool
  description = "Whether to use OIDC"
  default     = false
}

variable "tenant_id" {
  type        = string
  description = "The ID of the tenant"
}

variable "subscription_id" {
  type        = string
  description = "The ID of the subscription"
}

variable "client_id" {
  type        = string
  description = "The ID of the client"
}

variable "main_rg_name" {
  type        = string
  description = "The name of the main resource group"
  default     = "workbench"
}

variable "main_rg_location" {
  type        = string
  description = "The location of the main resource group"
  default     = "South East Asia"
}

variable "unused_variable" {
  type        = string
  description = "The unused variable"
  default     = "unused"
}

variable "manage_workbench_kv_secrets" {
  type        = bool
  description = "When true, write workbench_secrets into Key Vault (azurerm_key_vault_secret)."
  default     = false
}

variable "workbench_secrets" {
  description = <<-EOT
    Workbench credentials aligned with Helm global.workbenchPostgres / workbenchRabbitMq / workbenchRedis.
    Supply via a private tfvars file (e.g. vars/secrets.tfvars); never commit real values.
  EOT
  type = object({
    postgres_connection_string = string
    postgres_user              = string
    postgres_password          = string
    postgres_database          = string
    rabbitmq_uri               = string
    rabbitmq_password          = string
    redis_connection_string    = string
    redis_user                 = string
    redis_password             = string
  })
  sensitive = true
  default = {
    postgres_connection_string = ""
    postgres_user              = ""
    postgres_password          = ""
    postgres_database          = ""
    rabbitmq_uri               = ""
    rabbitmq_password          = ""
    redis_connection_string    = ""
    redis_user                 = ""
    redis_password             = ""
  }
}
