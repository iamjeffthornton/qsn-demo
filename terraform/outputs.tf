# ============================================================
# outputs.tf — What Terraform prints after it builds everything
# ============================================================
# WHAT THIS IS:
#   After "terraform apply" finishes, these values get printed
#   to your terminal. They're the addresses and names you need
#   to connect your CI/CD pipeline to the new infrastructure.
#
#   Think of it like a receipt after buying a house —
#   here's the address, here's the key, here's the utilities.
# ============================================================


# ---- RESOURCE GROUP ----
output "resource_group_name" {
  description = "Name of the Azure Resource Group"
  value       = azurerm_resource_group.qsn.name
}


# ---- KUBERNETES CLUSTER ----
output "aks_cluster_name" {
  description = "Name of the AKS cluster — use this in kubectl commands"
  value       = azurerm_kubernetes_cluster.qsn.name
}

output "aks_connect_command" {
  description = "Run this command to connect kubectl to your new AKS cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.qsn.name} --name ${azurerm_kubernetes_cluster.qsn.name}"
}


# ---- CONTAINER REGISTRY ----
output "acr_login_server" {
  description = "The address of your Container Registry — use in docker push commands"
  value       = azurerm_container_registry.qsn.login_server
}

output "docker_push_command" {
  description = "Run this to push your QSN agent image to Azure"
  value       = "docker push ${azurerm_container_registry.qsn.login_server}/qsn-agent:1.0"
}


# ---- KEY VAULT ----
output "key_vault_name" {
  description = "Name of the Key Vault storing your API keys"
  value       = azurerm_key_vault.qsn.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.qsn.vault_uri
}


# ---- LOG ANALYTICS ----
output "log_analytics_workspace_id" {
  description = "ID of Log Analytics — connect your monitoring dashboards here"
  value       = azurerm_log_analytics_workspace.qsn.id
}

output "log_query_example" {
  description = "Example KQL query to see your agent logs in Azure Monitor"
  value       = "ContainerLog | where LogEntry contains 'qsn_agent' | order by TimeGenerated desc | take 50"
}


# ---- SUMMARY ----
output "deployment_summary" {
  description = "Full summary of what was built"
  value = <<-EOT

  ╔══════════════════════════════════════════════════════╗
  ║     QSN Agent Stack — Deployed Successfully          ║
  ╠══════════════════════════════════════════════════════╣
  ║  Client:     ${var.client_name}
  ║  Environment:${var.environment}
  ║  Location:   ${var.location}
  ║  Replicas:   ${var.replica_count}
  ╠══════════════════════════════════════════════════════╣
  ║  NEXT STEPS:                                         ║
  ║  1. Run the aks_connect_command output above         ║
  ║  2. Run the docker_push_command output above         ║
  ║  3. kubectl apply -f k8s/                            ║
  ║  4. kubectl get pods -w                              ║
  ╚══════════════════════════════════════════════════════╝

  EOT
}
