# ============================================================
# main.tf
#
# WHAT IS THIS?
# -------------
# The core infrastructure definition for the n8n deployment.
# This file describes every Azure resource Terraform will create,
# update, or destroy. Terraform reads this and compares it to
# the current state file to work out what actions are needed.
#
# RESOURCES CREATED
# -----------------
# 1. Resource Group        — logical container for everything
# 2. Storage Account       — holds the Azure Files share
# 3. Azure Files Share     — persistent disk for n8n data
# 4. App Service Plan      — the underlying compute (B1 Linux)
# 5. Linux Web App         — the n8n Docker container
# 6. Custom Domain Binding — links n8n.scottbehan.dev to the app
# 7. Managed Certificate   — free TLS cert from App Service
# 8. Certificate Binding   — attaches cert to the custom domain
# ============================================================

# --- Terraform configuration block --------------------------
# Declares which version of Terraform and which providers are
# required. Terraform will error if these requirements aren't met.
terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.110" # ~> means >= 3.110 and < 4.0 (minor updates ok, no breaking major)
    }
  }
}

# --- Provider configuration ----------------------------------
# Tells Terraform to use the Azure Resource Manager provider.
# Authentication is handled via ARM_* environment variables
# (CLIENT_ID, CLIENT_SECRET, SUBSCRIPTION_ID, TENANT_ID) —
# these are never hardcoded here.
provider "azurerm" {
  features {} # Required block — enables default provider behaviour
}

# ── 1. Resource Group ─────────────────────────────────────────
# A resource group is a logical container in Azure.
# All n8n resources live here so they can be managed, monitored,
# and deleted together. Separate from the tfstate RG so you can
# tear down n8n without affecting Terraform state storage.
resource "azurerm_resource_group" "n8n" {
  name     = var.resource_group_name # rg-n8n-prod-eun
  location = var.location            # northeurope
  tags     = var.tags
}

# ── 2. Storage Account ────────────────────────────────────────
# This storage account hosts the Azure Files share that n8n
# uses for persistent data storage (SQLite database, encryption
# keys, workflow files). Without this, all n8n data is lost
# every time the container restarts.
#
# Standard_LRS = Locally Redundant Storage (3 copies in one DC)
# Sufficient for personal use — upgrade to ZRS/GRS for prod.
resource "azurerm_storage_account" "n8n" {
  name                     = "stn8nsbprod" # CAF: st<workload><env> — no hyphens allowed
  resource_group_name      = azurerm_resource_group.n8n.name
  location                 = azurerm_resource_group.n8n.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2" # Enforce modern TLS — TLS1_0/1.1 are deprecated
  tags                     = var.tags
}

# ── 3. Azure Files Share ──────────────────────────────────────
# A file share inside the storage account — behaves like a
# network drive. It gets mounted into the Docker container at
# /home/node/.n8n so n8n reads/writes its data there.
# quota = maximum size in GB. 10GB is plenty for personal use.
resource "azurerm_storage_share" "n8n_data" {
  name                 = "n8n-data"
  storage_account_name = azurerm_storage_account.n8n.name
  quota                = 10 # GB
}

# ── 4. App Service Plan ───────────────────────────────────────
# The App Service Plan defines the compute tier for the web app.
# Think of it like the VM size/spec that runs your containers.
#
# B1 = Basic tier, 1 vCore, 1.75GB RAM — enough for personal n8n.
# os_type = Linux required for Docker container deployments.
resource "azurerm_service_plan" "n8n" {
  name                = "asp-n8n-prod-eun" # CAF: asp-<workload>-<env>-<region>
  resource_group_name = azurerm_resource_group.n8n.name
  location            = azurerm_resource_group.n8n.location
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = var.tags
}

# ── 5. Linux Web App (n8n container) ─────────────────────────
# The actual App Service instance running the n8n Docker image.
# App Service pulls the image from Docker Hub on startup and
# mounts the Azure Files share for persistent storage.
resource "azurerm_linux_web_app" "n8n" {
  name                = "app-n8n-prod-eun" # CAF: app-<workload>-<env>-<region>
  resource_group_name = azurerm_resource_group.n8n.name
  location            = azurerm_resource_group.n8n.location
  service_plan_id     = azurerm_service_plan.n8n.id
  https_only          = true # Redirect all HTTP traffic to HTTPS
  tags                = var.tags

  site_config {
    # always_on keeps the app warm so it responds instantly.
    # On B1 this is supported but uses more compute — set to
    # true if cold start times are a problem for you.
    always_on = false

    application_stack {
      docker_image_name   = "n8nio/n8n:latest"  # Official n8n Docker image
      docker_registry_url = "https://docker.io" # Docker Hub
    }

    # App Service uses this path to check if the container is
    # healthy. If /healthz stops responding, App Service will
    # restart the container automatically.
    health_check_path = "/healthz"

    ip_restriction_default_action = "Deny"

    ip_restriction {
      name        = "home"
      ip_address  = "${var.home_ip}/32"
      action      = "Allow"
      priority    = 100
      description = "Scott home IP"
    }

    ip_restriction {
      name        = "azure-health-check"
      service_tag = "AzureCloud"
      action      = "Allow"
      priority    = 200
      description = "Azure internal health check"
    }
  }

  # --- Application settings (environment variables) ----------
  # These are injected into the container as env vars at runtime.
  # Sensitive values (encryption key) come from Terraform variables
  # which are sourced from GitHub Secrets — never hardcoded.
  app_settings = {
    # Tell n8n what hostname it's running on so it generates
    # correct URLs for webhooks and the UI
    N8N_HOST     = var.custom_hostname # n8n.scottbehan.dev
    N8N_PROTOCOL = "https"
    N8N_PORT     = "5678" # n8n's default internal port

    # Webhook URL — must match your public domain so that
    # external services (Slack, GitHub, etc.) can trigger workflows
    WEBHOOK_URL = "https://${var.custom_hostname}/"

    # Encryption key for n8n's credential store.
    # n8n encrypts saved credentials (API keys, passwords) at rest.
    # This key is what unlocks them — keep it safe and backed up.
    N8N_ENCRYPTION_KEY = var.n8n_encryption_key

    # Where n8n stores its data inside the container.
    # This path is where the Azure Files share is mounted below.
    N8N_USER_FOLDER = "/home/node/n8n-data"

    # Disable telemetry and update notifications for personal use
    N8N_DIAGNOSTICS_ENABLED           = "false"
    N8N_VERSION_NOTIFICATIONS_ENABLED = "false"

    # Timezone settings — affects cron schedule nodes in workflows
    GENERIC_TIMEZONE = "Europe/London"
    TZ               = "Europe/London"

    # Tell App Service which port the container listens on.
    # Without this App Service won't know how to route traffic.
    WEBSITES_PORT = "5678"

    # Pull the latest Docker image whenever the app restarts.
    # Useful for staying up to date with n8n releases.
    DOCKER_ENABLE_CI = "true"
  }

  # --- Azure Files mount -------------------------------------
  # Mounts the Azure Files share into the container so n8n's
  # data directory is backed by persistent cloud storage.
  # If the container restarts or is redeployed, all data persists.
  storage_account {
    name         = "n8n-data"                                     # Internal reference name
    type         = "AzureFiles"                                   # Mount type
    account_name = azurerm_storage_account.n8n.name               # Which storage account
    share_name   = azurerm_storage_share.n8n_data.name            # Which file share
    access_key   = azurerm_storage_account.n8n.primary_access_key # Auth key
    mount_path   = "/home/node/n8n-data"                          # Where to mount inside container
  }

  # --- Logging -----------------------------------------------
  # Retains HTTP access logs for 7 days. View them with:
  # az webapp log tail --name app-n8n-prod-eun --resource-group rg-n8n-prod-eun
  logs {
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 35
      }
    }
  }
}

# ── 6. Custom Domain Binding ──────────────────────────────────
# Links n8n.scottbehan.dev to this App Service.
# IMPORTANT: The Cloudflare CNAME record must exist BEFORE this
# resource is applied — App Service validates DNS ownership.
# See README for the two-pass deployment approach.
resource "azurerm_app_service_custom_hostname_binding" "n8n" {
  hostname            = var.custom_hostname # n8n.scottbehan.dev
  app_service_name    = azurerm_linux_web_app.n8n.name
  resource_group_name = azurerm_resource_group.n8n.name
  depends_on          = [azurerm_linux_web_app.n8n]
}

# ── 7. Managed Certificate ────────────────────────────────────
# App Service can provision and renew a free TLS certificate
# for your custom domain automatically. No cert management needed.
# The cert is tied to the custom hostname binding above.
resource "azurerm_app_service_managed_certificate" "n8n" {
  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.n8n.id
}

# ── 8. Certificate Binding ────────────────────────────────────
# Attaches the managed certificate to the custom domain so
# HTTPS works on n8n.scottbehan.dev.
# SNI = Server Name Indication — modern TLS standard that allows
# multiple certs on one IP address.
resource "azurerm_app_service_certificate_binding" "n8n" {
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.n8n.id
  certificate_id      = azurerm_app_service_managed_certificate.n8n.id
  ssl_state           = "SniEnabled"
}
#--9. Resource Alert -------------------------------------------
#sets the alert for resource consumption
resource "azurerm_consumption_budget_resource_group" "n8n" {
  name              = "budget-n8n-prod-eun"
  resource_group_id = azurerm_resource_group.n8n.id

  amount     = 20
  time_grain = "Monthly"

  time_period {
    start_date = "2026-03-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.budget_alert_email]
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.budget_alert_email]
  }
}