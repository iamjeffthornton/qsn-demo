# ============================================================
# QSN Rugby Agent Stack — Terraform Infrastructure as Code
# ============================================================
# WHAT THIS FILE DOES:
#   Creates the complete Azure infrastructure for your QSN
#   LangGraph agent in one command: terraform apply
#
# WHAT GETS BUILT:
#   1. Resource Group     — the folder that holds everything
#   2. Container Registry — stores your Docker images
#   3. Key Vault          — stores your API keys securely
#   4. Kubernetes Cluster — runs your 3 agent replicas
#   5. Log Analytics      — captures all your agent logs
#   6. Monitor Alerts     — notifies you when things break
#
# HOW TO USE:
#   terraform init      (download Azure provider — do once)
#   terraform plan      (preview what will be created)
#   terraform apply     (build everything — ~5 minutes)
#   terraform destroy   (tear everything down when done)
# ============================================================


# ============================================================
# PROVIDER — tells Terraform "we're building on Azure"
# ============================================================
# Think of this like telling a rugby team which stadium to play in.
# "azurerm" = Azure Resource Manager = Microsoft Azure

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.85.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }

  # ---- REMOTE STATE (uncomment when working in a team) ----
  # Stores Terraform state in Azure Blob Storage so the whole
  # team shares the same state file, not just your laptop.
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "stterraformqsn"
  #   container_name       = "tfstate"
  #   key                  = "qsn-agent.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}


# ============================================================
# RANDOM SUFFIX — makes names globally unique
# ============================================================
# Azure requires some names to be globally unique (like domain names).
# A random 4-character suffix prevents naming conflicts.
# Example: "acrqsnusa3f2" instead of just "acrqsnusa"

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result

  # Standard tags applied to EVERY resource
  # Tags track ownership and billing across all environments
  common_tags = {
    Project     = "QSN-Rugby-Agent"
    Environment = var.environment
    Owner       = var.owner_name
    ManagedBy   = "Terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }
}


# ============================================================
# 1. RESOURCE GROUP — the folder that holds everything
# ============================================================
# In Azure, a Resource Group is like a rugby team's kit bag.
# Every resource (cluster, registry, vault) lives inside one.
# Delete the Resource Group and everything inside it is gone.
# Perfect for spinning up a demo and tearing it down cleanly
# when the match is over.

resource "azurerm_resource_group" "qsn" {
  name     = "rg-${var.league_name}-qsn-${local.suffix}"
  location = var.location
  tags     = local.common_tags
}


# ============================================================
# 2. CONTAINER REGISTRY — stores your Docker images
# ============================================================
# Remember: docker build -t qsn-agent:1.0 .
# That image lives on your laptop right now.
# Azure Container Registry (ACR) is the private Docker Hub
# where images live in the cloud. Your K8s cluster pulls
# from ACR instead of your laptop.
#
# Think of it like QSN's private video archive — all match
# footage stored centrally so any coach can pull it anywhere.

resource "azurerm_container_registry" "qsn" {
  name                = "acrqsn${var.league_name}${local.suffix}"
  resource_group_name = azurerm_resource_group.qsn.name
  location            = azurerm_resource_group.qsn.location
  sku                 = var.environment == "production" ? "Standard" : "Basic"
  admin_enabled       = false

  tags = local.common_tags
}


# ============================================================
# 3. KEY VAULT — stores your API keys securely
# ============================================================
# Your Anthropic API key never goes in code or YAML files.
# Key Vault is the enterprise-grade secret store.
# Pods request the key at runtime using their Azure identity.
#
# Think of it like the match officials' secure safe — only
# authorised people can access it, and every access is logged.

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "qsn" {
  name                       = "kv-qsn-${var.league_name}-${local.suffix}"
  resource_group_name        = azurerm_resource_group.qsn.name
  location                   = azurerm_resource_group.qsn.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  tags = local.common_tags
}

# Store the Anthropic API key — value comes from variables,
# never hardcoded directly in this file
resource "azurerm_key_vault_secret" "anthropic_key" {
  name            = "anthropic-api-key"
  value           = var.anthropic_api_key
  key_vault_id    = azurerm_key_vault.qsn.id
  expiration_date = "2026-12-31T00:00:00Z"
}


# ============================================================
# 4. LOG ANALYTICS — captures all your agent logs
# ============================================================
# Every agent emits structured JSON logs:
#   {"agent":"router","status":"success","tokens":183,"latency_ms":782}
#
# Log Analytics stores those logs and lets you query them:
#   "Show me all agents that took more than 5 seconds"
#   "Show me total token spend per agent this week"
#   "Show me every error in the last 24 hours"
#
# Think of it like the match stats ticker — every play recorded,
# searchable, and reviewable long after the final whistle.

resource "azurerm_log_analytics_workspace" "qsn" {
  name                = "law-qsn-${var.league_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.qsn.name
  location            = azurerm_resource_group.qsn.location
  retention_in_days   = var.environment == "production" ? 90 : 30

  tags = local.common_tags
}


# ============================================================
# 5. KUBERNETES CLUSTER (AKS) — runs your agent replicas
# ============================================================
# Last night you ran: k3d cluster create qsn-cluster
# This creates the same thing but on Azure — production grade.
# Microsoft manages the control plane. You deploy workloads.
# Your 3 agent pods run here with auto-scaling and self-healing.
#
# Think of it like a full stadium with automatic capacity —
# more fans arrive, more gates open. A gate breaks, it gets
# replaced instantly without stopping the match.

resource "azurerm_kubernetes_cluster" "qsn" {
  name                = "aks-qsn-${var.league_name}-${local.suffix}"
  location            = azurerm_resource_group.qsn.location
  resource_group_name = azurerm_resource_group.qsn.name
  dns_prefix          = "qsn-${var.league_name}-${local.suffix}"

  default_node_pool {
    name            = "agentpool"
    node_count      = var.environment == "production" ? 3 : 1
    vm_size         = var.node_vm_size
    os_disk_size_gb = 50

    # Auto-scaling: adds nodes automatically when load spikes
    enable_auto_scaling = var.environment == "production" ? true : false
    min_count           = var.environment == "production" ? 2 : null
    max_count           = var.environment == "production" ? 5 : null
  }

  # SystemAssigned = AKS gets its own Azure identity
  # Used to pull images from ACR without passwords
  identity {
    type = "SystemAssigned"
  }

  # Connect AKS to Log Analytics — all pod logs flow there
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.qsn.id
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = local.common_tags
}

# Give AKS permission to pull images from ACR
# Managed Identity — no passwords, no credentials in code
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.qsn.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.qsn.id
  skip_service_principal_aad_check = true
}


# ============================================================
# 6. MONITORING ALERTS — get notified when things break
# ============================================================
# Sends an email when your agent pods are crashing repeatedly.
# Like a team physio getting an instant alert when a player
# goes down — immediate awareness, immediate response.

resource "azurerm_monitor_action_group" "qsn_alerts" {
  name                = "ag-qsn-${var.league_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.qsn.name
  short_name          = "qsnalerts"

  email_receiver {
    name          = "ops-team"
    email_address = var.alert_email
  }

  tags = local.common_tags
}
