# ============================================================
# variables.tf — All the inputs your Terraform config needs
# ============================================================
# WHAT THIS IS:
#   Think of variables like function parameters in Python.
#   Instead of hardcoding "qrail" or "eastus" everywhere,
#   you define them here and pass different values per client.
#
#   Queensland Rail:  client_name = "qrail",   location = "australiaeast"
#   US Energy:        client_name = "usenergy", location = "eastus"
#   UK Finance:       client_name = "ukfin",    location = "uksouth"
#
#   Same code. Different variables. Different environments.
#   That is the power of Infrastructure as Code.
# ============================================================


# ---- CLIENT IDENTITY ----

variable "client_name" {
  description = "Short name for the client — used in all resource names"
  type        = string

  validation {
    # Must be lowercase letters only, max 8 chars
    # Azure has strict naming rules for some resources
    condition     = can(regex("^[a-z]{2,8}$", var.client_name))
    error_message = "client_name must be 2-8 lowercase letters only."
  }
}

variable "owner_name" {
  description = "Your name — appears in resource tags for ownership tracking"
  type        = string
  default     = "Jeff Thornton"
}


# ---- ENVIRONMENT ----

variable "environment" {
  description = "Which environment: dev, staging, or production"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be dev, staging, or production."
  }
}


# ---- AZURE LOCATION ----

variable "location" {
  description = "Azure region where everything gets deployed"
  type        = string
  default     = "eastus"

  # Common Azure regions:
  # "eastus"          = Virginia, USA (cheapest, most services)
  # "westus2"         = Washington, USA
  # "australiaeast"   = Sydney, Australia (Queensland Rail)
  # "uksouth"         = London, UK
  # "germanywestcentral" = Frankfurt, Germany (EU data residency)
}


# ---- KUBERNETES ----

variable "node_vm_size" {
  description = "Azure VM size for Kubernetes nodes"
  type        = string
  default     = "Standard_D2s_v3"   # 2 CPU, 8GB RAM — good for dev

  # Production options:
  # "Standard_D4s_v3"  = 4 CPU, 16GB RAM  (recommended for AI agents)
  # "Standard_D8s_v3"  = 8 CPU, 32GB RAM  (heavy workloads)
}

variable "replica_count" {
  description = "How many agent pod replicas to run"
  type        = number
  default     = 3

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 10
    error_message = "replica_count must be between 1 and 10."
  }
}


# ---- SECRETS ----
# IMPORTANT: Never put actual secret values in this file.
# Pass them via environment variables or a .tfvars file
# that is listed in .gitignore (never committed to GitHub).

variable "anthropic_api_key" {
  description = "Your Anthropic API key — stored in Key Vault, never in code"
  type        = string
  sensitive   = true   # Terraform hides this in all output and logs
}


# ---- MONITORING ----

variable "alert_email" {
  description = "Email address to receive production alerts"
  type        = string
  default     = "jeff@jeffreythornton.com"
}
