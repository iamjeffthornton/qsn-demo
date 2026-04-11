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
#   6. Monitor Workspace  — dashboards and alerts
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
# Think of this like telling a contractor which city to work in.
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
  # Stores the Terraform state file in Azure Blob Storage
  # so the whole team shares the same state, not just your laptop
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
      # When you delete the Key Vault, also delete its contents
      purge_soft_delete_on_destroy = true
    }
  }
}


# ============================================================
# RANDOM SUFFIX — makes names globally unique
# ============================================================
# Azure requires some resource names to be globally unique
# (like domain names). Adding a random 4-character suffix
# prevents naming conflicts across different deployments.
# Example: "acr-qsn-a3f2" instead of just "acr-qsn"

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

locals {
  # Build a consistent suffix used across all resource names
  suffix = random_string.suffix.result

  # Standard tags applied to EVERY resource
  # In enterprise Azure, tags = billing tracking + ownership
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
# In Azure, a Resource Group is like a project folder.
# Every Azure resource (cluster, registry, vault) must live
# inside one. Delete the Resource Group = delete everything in it.
# Useful for client teardown: one command removes the whole stack.

resource "azurerm_resource_group" "qsn" {
  name     = "rg-${var.client_name}-qsn-${local.suffix}"
  location = var.location
  tags     = local.common_tags
}


# ============================================================
# 2. CONTAINER REGISTRY — stores your Docker images
# ============================================================
# Remember last night? You ran:
#   docker build -t qsn-agent:1.0 .
#
# That image lives on your laptop. Azure Container Registry (ACR)
# is the private Docker Hub where your images live in the cloud.
# Your K8s cluster pulls from ACR instead of your laptop.
#
# It's like uploading your QSN videos to a private YouTube
# before pushing them to the public channel.

resource "azurerm_container_registry" "qsn" {
  name                = "acrqsn${var.client_name}${local.suffix}"
  resource_group_name = azurerm_resource_group.qsn.name
  location            = azurerm_resource_group.qsn.location

  # Standard = private registry with geo-replication available
  # Basic = cheapest (good for dev/demo)
  # Premium = enterprise features (vulnerability scanning, etc.)
  sku = var.environment == "production" ? "Standard" : "Basic"

  # Allow the AKS cluster to pull images without passwords
  # Uses Azure Managed Identity instead — more secure
  admin_enabled = false

  tags = local.common_tags
}


# ============================================================
# 3. KEY VAULT — stores your API keys securely
# ============================================================
# Remember: you never hardcode your Anthropic API key.
# Last night you stored it as a K8s Secret.
# In Azure, Key Vault is the enterprise-grade version of that.
#
# Think of it like a bank vault for secrets.
# Your pods request the key at runtime using their identity.
# The key never appears in any file, log, or code.

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "qsn" {
  name                = "kv-qsn-${var.client_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.qsn.name
  location            = azurerm_resource_group.qsn.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # Standard = software-protected keys (good for most use cases)
  # Premium  = hardware-protected keys (regulated industries)
  sku_name = "standard"

  # Soft delete = deleted secrets recoverable for 7 days
  # Prevents accidental permanent deletion
  soft_delete_retention_days = 7
  purge_protection_enabled   = false  # set true in regulated industries

  # Who can access this vault
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  tags = local.common_tags
}

# Store the Anthropic API key in Key Vault
# Value comes from your variables (never hardcoded here)
resource "azurerm_key_vault_secret" "anthropic_key" {
  name         = "anthropic-api-key"
  value        = var.anthropic_api_key
  key_vault_id = azurerm_key_vault.qsn.id

  # Tag with expiry reminder (good practice for API keys)
  expiration_date = "2026-12-31T00:00:00Z"
}


# ============================================================
# 4. LOG ANALYTICS — captures all your agent logs
# ============================================================
# Remember the structured JSON logs your agents emit?
#   {"agent":"router","status":"success","tokens":183,"latency_ms":782}
#
# Log Analytics is where those logs live in Azure.
# You can query them like a database:
#   "Show me all agent calls that took more than 5 seconds"
#   "Show me total token spend per agent this week"
#   "Show me every error in the last 24 hours"

resource "azurerm_log_analytics_workspace" "qsn" {
  name                = "law-qsn-${var.client_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.qsn.name
  location            = azurerm_resource_group.qsn.location

  # How many days to keep logs before auto-deletion
  # 30 days = good for dev, 90+ days = enterprise compliance
  retention_in_days = var.environment == "production" ? 90 : 30

  tags = local.common_tags
}


# ============================================================
# 5. KUBERNETES CLUSTER (AKS) — runs your agent replicas
# ============================================================
# This is the big one. Last night you created a local K8s
# cluster with: k3d cluster create qsn-cluster
#
# This creates the same thing but on Azure (AKS).
# Microsoft manages the control plane — you just deploy workloads.
# Your 3 agent pods run here, with auto-scaling and self-healing.

resource "azurerm_kubernetes_cluster" "qsn" {
  name                = "aks-qsn-${var.client_name}-${local.suffix}"
  location            = azurerm_resource_group.qsn.location
  resource_group_name = azurerm_resource_group.qsn.name

  # The DNS prefix for your cluster's API endpoint
  dns_prefix = "qsn-${var.client_name}-${local.suffix}"

  # ---- DEFAULT NODE POOL ----
  # A "node pool" is a group of VMs that run your pods.
  # Each node can run multiple pods (agent replicas).
  default_node_pool {
    name = "agentpool"

    # How many VMs in the pool
    # Production: 3 nodes for high availability
    # Dev: 1 node to save cost
    node_count = var.environment == "production" ? 3 : 1

    # VM size — D4s_v3 = 4 CPU, 16GB RAM
    # Good for AI workloads that call external APIs
    vm_size = var.node_vm_size

    # Auto-scaling: if load spikes, add more nodes automatically
    enable_auto_scaling = var.environment == "production" ? true : false
    min_count           = var.environment == "production" ? 2 : null
    max_count           = var.environment == "production" ? 5 : null

    # Where the node OS disk lives (faster than default)
    os_disk_size_gb = 50
  }

  # ---- IDENTITY ----
  # SystemAssigned = AKS gets its own Azure identity automatically
  # This identity is used to pull images from ACR without passwords
  identity {
    type = "SystemAssigned"
  }

  # ---- MONITORING ----
  # Connect AKS to your Log Analytics workspace
  # All pod logs, metrics, and events flow there automatically
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.qsn.id
  }

  # ---- NETWORK ----
  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }

  tags = local.common_tags
}

# ---- CONNECT AKS TO ACR ----
# Give the AKS cluster permission to pull images from your
# Container Registry without needing a username/password.
# This is Managed Identity in action — secure, no credentials.
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.qsn.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.qsn.id
  skip_service_principal_aad_check = true
}


# ============================================================
# 6. MONITORING ALERTS — get notified when things break
# ============================================================
# This creates an alert that fires when your agent pods
# have a high restart count — meaning they're crashing.
# Azure sends an email to the ops team automatically.

resource "azurerm_monitor_action_group" "qsn_alerts" {
  name                = "ag-qsn-${var.client_name}-${local.suffix}"
  resource_group_name = azurerm_resource_group.qsn.name
  short_name          = "qsnalerts"

  email_receiver {
    name          = "ops-team"
    email_address = var.alert_email
  }

  tags = local.common_tags
}
