# ============================================================
# variables.tf
#
# WHAT IS THIS?
# -------------
# Defines all the input variables Terraform accepts.
# Think of these like function parameters — they let you
# reuse the same Terraform code with different values.
#
# WHERE DO VALUES COME FROM?
# --------------------------
# 1. terraform.tfvars     — non-sensitive values committed to repo
# 2. TF_VAR_* env vars    — sensitive values injected at runtime
#                           e.g. TF_VAR_n8n_encryption_key
# 3. Default values below — used if nothing else is provided
#
# SENSITIVE VARIABLES
# -------------------
# Variables marked sensitive = true are redacted from
# Terraform plan/apply output so they never appear in logs.
# ============================================================

variable "location" {
  description = "Azure region to deploy all resources into"
  type        = string
  default     = "northeurope" # North Europe — lowest latency from Northampton
}

variable "resource_group_name" {
  description = "Name of the resource group for all n8n resources"
  type        = string
  default     = "rg-n8n-prod-eun" # CAF: rg-<workload>-<env>-<region>
}

variable "custom_hostname" {
  description = "Custom domain for n8n, e.g. n8n.scottbehan.dev"
  type        = string
  # No default — must be explicitly provided via tfvars or TF_VAR_custom_hostname
  # Set via GitHub Secret N8N_HOSTNAME → TF_VAR_custom_hostname in CI
}

variable "n8n_encryption_key" {
  description = <<-EOT
    Encryption key used by n8n to encrypt credentials stored in its database.
    Generate with: openssl rand -hex 32
    WARNING: If you lose this key, all saved credentials in n8n are unrecoverable.
    Store it safely in GitHub Secrets and never commit it to the repo.
  EOT
  type      = string
  sensitive = true # Redacted from all Terraform output and logs
  # Set via GitHub Secret N8N_ENCRYPTION_KEY → TF_VAR_n8n_encryption_key in CI
}

variable "tags" {
  description = "Tags applied to all resources — useful for cost tracking and filtering in the portal"
  type        = map(string)
  default = {
    project     = "n8n"
    environment = "prod"
    managed_by  = "terraform" # Makes it clear in the portal these resources are IaC managed
  }
}
