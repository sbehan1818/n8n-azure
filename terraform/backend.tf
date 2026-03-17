# ============================================================
# backend.tf
#
# WHAT IS THIS?
# -------------
# This file tells Terraform WHERE to store its state file.
# Instead of saving state locally on your machine (the default),
# we store it remotely in Azure Blob Storage so that:
#   - GitHub Actions can access it during CI/CD runs
#   - State is never lost if your laptop dies
#   - Multiple people/tools can work against the same state
#
# The storage account was created by bootstrap-state.sh BEFORE
# Terraform was initialised — see that script for the why.
#
# HOW DOES TERRAFORM AUTHENTICATE TO THE BACKEND?
# ------------------------------------------------
# Via the ARM_ACCESS_KEY environment variable. This is never
# hardcoded here — it's injected at runtime from GitHub Secrets
# (in CI) or your local environment (when running locally).
# ============================================================

terraform {
  backend "azurerm" {
    # Resource group that contains the state storage account.
    # Deliberately separate from the n8n project RG so it
    # survives if you ever destroy the n8n infrastructure.
    resource_group_name = "rg-tfstate-shared-uks"

    # The storage account created by bootstrap-state.sh.
    # Name must be globally unique across all of Azure.
    storage_account_name = "stscotttfstateuks"

    # The blob container inside the storage account.
    # One container can hold state files for multiple projects
    # separated by the unique key below.
    container_name = "tfstate"

    # The path/filename for THIS project's state file.
    # Using a folder-style prefix (n8n/) means you can add
    # future projects here too e.g. blog/terraform.tfstate
    key = "n8n/terraform.tfstate"

    # ARM_ACCESS_KEY is NOT set here — supplied at runtime via
    # environment variable from GitHub Secrets or locally:
    # export ARM_ACCESS_KEY="<your-key>"
  }
}
