output "service_account_name" {
  description = "ServiceAccount name the Deployments must reference."
  value       = kubernetes_service_account_v1.app.metadata[0].name
}

output "role_name" {
  description = "Role name granted to the ServiceAccount, or null when no rules were requested."
  value       = length(kubernetes_role_v1.app) > 0 ? kubernetes_role_v1.app[0].metadata[0].name : null
}
