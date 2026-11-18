output "namespace" {
  description = "Namespace created for this environment."
  value       = module.namespace.name
}

output "service_account_name" {
  description = "ServiceAccount the Deployments must reference."
  value       = module.rbac.service_account_name
}

output "environment" {
  description = "Environment name, used by GitOps overlays."
  value       = local.environment
}

output "services" {
  description = "Services deployed into this environment."
  value       = local.services
}
