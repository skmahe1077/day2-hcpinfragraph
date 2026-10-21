output "vault_public_endpoint_url" {
  value = hcp_vault_cluster.demo.vault_public_endpoint_url
}

output "vault_namespace" {
  value = hcp_vault_cluster.demo.namespace
}

output "admin_token" {
  value     = hcp_vault_cluster_admin_token.demo.token
  sensitive = true
}
