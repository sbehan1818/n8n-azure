#!/usr/bin/env bash
# ============================================================
# bootstrap-state.sh
#
# WHAT IS THIS?
# ------------
# Terraform needs to store a "state file" — a record of every
# Azure resource it has created and manages. For a personal or
# team deployment you want that state file stored remotely
# (in Azure Blob Storage) rather than on your local machine.
#
# WHY CAN'T TERRAFORM CREATE THIS ITSELF?
# ----------------------------------------
# This is the classic chicken-and-egg problem with Terraform
# remote state. Terraform needs somewhere to store state
# BEFORE it can run — but you can't use Terraform to create
# that storage because it has no state yet to track it.
# The solution: create this one storage account manually using
# the Azure CLI, just once, before Terraform ever runs.
# Everything else (n8n app, storage for data, etc.) is then
# managed entirely by Terraform going forward.
#
# WHEN DO I RUN THIS?
# -------------------
# Once only — before your first `terraform init`.
# If you destroy and rebuild the n8n infrastructure later,
# you do NOT need to re-run this. The state storage persists.
#
# NAMING CONVENTION (Microsoft CAF)
# -----------------------------------
# Resources follow the Microsoft Cloud Adoption Framework (CAF)
# naming standard: <type>-<workload>-<environment>-<region>
#   rg-tfstate-shared-uks   = resource group, tfstate workload,
#                             shared (not tied to one env), UK South
#   stscotttfstateuks        = storage account (no hyphens allowed,
#                             max 24 chars, globally unique)
# ============================================================

# --- Bash safety flags ---------------------------------------
# -e  : exit immediately if any command fails
# -u  : treat unset variables as errors (prevents silent bugs)
# -o pipefail : catch failures inside piped commands too
set -euo pipefail

# --- Config (edit these if reusing for another project) ------
LOCATION="uksouth"                  # Azure region — UK South
RG_STATE="rg-tfstate-shared-uks"   # Resource group for ALL Terraform state (shared across projects)
SA_NAME="stscotttfstateuks"        # Storage account name — must be globally unique across ALL of Azure,
                                    # 3-24 chars, lowercase alphanumeric only, no hyphens
CONTAINER_NAME="tfstate"           # Blob container inside the storage account
# -------------------------------------------------------------

# --- Step 1: Create the resource group -----------------------
# A resource group is a logical container for Azure resources.
# We use a dedicated RG for state so it is never accidentally
# deleted when tearing down a project's own resource group.
echo "==> Creating resource group: $RG_STATE (CAF: rg-<workload>-<env>-<region>)"
az group create \
  --name "$RG_STATE" \
  --location "$LOCATION" \
  --output table

# --- Step 2: Create the storage account ----------------------
# Standard_LRS = Locally Redundant Storage — 3 copies within
# one datacenter. Sufficient and cheapest option for state files.
# StorageV2 = current generation, supports all features.
# TLS1_2 = enforce minimum TLS version for security.
# allow-blob-public-access false = no anonymous access to blobs.
echo "==> Creating storage account: $SA_NAME"
az storage account create \
  --name "$SA_NAME" \
  --resource-group "$RG_STATE" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output table

# --- Step 3: Create the blob container -----------------------
# A container is like a folder inside the storage account.
# Terraform will write one state file per project into here,
# identified by a unique key (e.g. n8n/terraform.tfstate).
# auth-mode login = use your current Azure CLI credentials
# rather than a storage account key for this operation.
echo "==> Creating blob container: $CONTAINER_NAME"
az storage container create \
  --name "$CONTAINER_NAME" \
  --account-name "$SA_NAME" \
  --auth-mode login \
  --output table

# --- Step 4: Print outputs -----------------------------------
# Remind the user what values to put in backend.tf and which
# secret to add to GitHub Actions.
echo ""
echo "==> Bootstrap complete. These values are already set in your backend.tf:"
echo "    storage_account_name = \"$SA_NAME\""
echo "    container_name       = \"$CONTAINER_NAME\""
echo "    key                  = \"n8n/terraform.tfstate\""
echo ""

# Retrieve storage account key — Terraform uses this to
# authenticate against the state backend at runtime.
# The key is fetched using a JMESPath query ([0].value)
# which pulls the first key's value from the keys list.
echo "==> Add this as a GitHub Actions secret named ARM_ACCESS_KEY:"
SA_KEY=$(az storage account keys list \
  --account-name "$SA_NAME" \
  --resource-group "$RG_STATE" \
  --query "[0].value" -o tsv)
echo "    ARM_ACCESS_KEY = $SA_KEY"
echo ""
echo "==> Keep this key secure — treat it like a password."