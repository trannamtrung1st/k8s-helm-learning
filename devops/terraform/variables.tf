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
