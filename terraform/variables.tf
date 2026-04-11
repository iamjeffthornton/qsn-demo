# ============================================================
# variables.tf — All the inputs your Terraform config needs
# ============================================================
# WHAT THIS IS:
#   Variables are like the lineup sheet before a match.
#   Instead of hardcoding team names and locations everywhere,
#   you define them here and swap values per deployment.
#
#   USA Eagles coverage:   league_name = "usaeagles", location = "eastus"
#   All Blacks coverage:   league_name = "allblacks", location = "australiaeast"
#   Six Nations coverage:  league_name = "sixnations", location = "uksouth"
#
#   Same infrastructure code. Different variables.
#   Different environments. That is Infrastructure as Code.
# ============================================================


# ---- LEAGUE / DEPLOYMENT IDENTITY ----

variable "league_name" {
  description = "Short name for the rugby league or coverage region — used in all resource names"
  type        = string
  default     = "qsnrugby"

  validation {
    # Lowercase letters only, 2-10 chars
    # Azure has strict naming rules for container registries
    condition     = can(regex("^[a-z]{2,10}$", var.league_name))
    error_message = "league_name must be 2-10 lowercase letters only. No spaces or hyphens."
  }
}

variable "owner_name" {
  description = "Your name — appears in resource tags for ownership tracking"
  type        = string
  default     = "Jeff Thornton"
}


# ---- ENVIRONMENT ----

variable "environment" {
  description = "Which environment to deploy: dev, staging, or production"
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

  # Common Azure regions for rugby coverage:
  # "eastus"           = Virginia, USA     (USA Eagles, Americas Rugby)
  # "westus2"          = Washington, USA   (Pacific coverage)
  # "australiaeast"    = Sydney, Australia (Super Rugby, Wallabies)
  # "uksouth"          = London, UK        (Premiership, Six Nations)
  # "francecentral"    = Paris, France     (Top 14, Six Nations)
  # "southafricanorth" = Johannesburg, SA  (URC, Springboks)
}


# ---- KUBERNETES ----

variable "node_vm_size" {
  description = "Azure VM size for each Kubernetes node"
  type        = string
  default     = "Standard_D2s_v3"  # 2 CPU, 8GB RAM — good for dev

  # Options by workload:
  # "Standard_D2s_v3"  = 2 CPU,  8GB  (dev/demo — cheapest)
  # "Standard_D4s_v3"  = 4 CPU,  16GB (recommended for live match coverage)
  # "Standard_D8s_v3"  = 8 CPU,  32GB (high-volume tournament coverage)
}

variable "replica_count" {
  description = "How many QSN agent pod replicas to run simultaneously"
  type        = number
  default     = 3

  # 1 = dev/demo (single pod, no redundancy)
  # 3 = standard production (one pod can fail, two keep running)
  # 5 = major tournament coverage (Six Nations, Rugby World Cup)

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 10
    error_message = "replica_count must be between 1 and 10."
  }
}


# ---- SECRETS ----
# IMPORTANT: Never put real secret values in this file.
# Pass them via environment variables or a terraform.tfvars
# file that is listed in .gitignore and NEVER committed to GitHub.

variable "anthropic_api_key" {
  description = "Anthropic API key — stored in Key Vault, never in code or logs"
  type        = string
  sensitive   = true  # Terraform hides this value in all output and plan files
}


# ---- MONITORING ----

variable "alert_email" {
  description = "Email address that receives production alerts when agents crash"
  type        = string
  default     = "jeff@jeffreythornton.com"
}
