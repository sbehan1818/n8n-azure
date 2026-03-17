# ============================================================
# outputs.tf
#
# WHAT IS THIS?
# -------------
# Outputs are values Terraform prints at the end of an apply.
# They're useful for:
#   - Getting values you need for the next manual step
#     (e.g. the App Service hostname to put in Cloudflare DNS)
#   - Referencing values from other Terraform modules
#   - Confirming what was actually deployed
#
# View outputs at any time (without re-running apply) with:
#   terraform output
# ============================================================

output "app_service_default_hostname" {
  description = <<-EOT
    The default Azure hostname for the App Service.
    You need this to create the Cloudflare CNAME record BEFORE
    the custom domain binding can be applied.
    Format: app-n8n-prod-uks.azurewebsites.net
    Use this as the CNAME target in Cloudflare (DNS only, not proxied).
  EOT
  value = azurerm_linux_web_app.n8n.default_hostname
}

output "app_service_name" {
  description = "Name of the App Service — used in az webapp CLI commands"
  value       = azurerm_linux_web_app.n8n.name
}

output "resource_group_name" {
  description = "Resource group containing all n8n resources"
  value       = azurerm_resource_group.n8n.name
}

output "storage_account_name" {
  description = "Name of the storage account used for Azure Files (n8n data persistence)"
  value       = azurerm_storage_account.n8n.name
}

output "n8n_url" {
  description = "The public URL your n8n instance will be accessible at once DNS and cert are set up"
  value       = "https://${var.custom_hostname}"
}
