# bituach-dev - development environment.
#
# Values come from handoff.md §4:
#   replicas 1, CPU 50m/250m, memory 64Mi/128Mi, quota 12 pods / 2 CPU / 2Gi,
#   HPA disabled, default-deny + explicit allows, developers can edit.
#
# Terraform owns namespaces, quota, limits, RBAC, ServiceAccounts, NetworkPolicy
# and HPA. Deployments/Services/Ingresses live in gitops/overlays/dev and are
# reconciled by Argo CD - see terraform/modules/README.md for why.

locals {
  environment = "dev"
  namespace   = "bituach-${local.environment}"
  services    = ["engine", "data", "ingest"]
}

module "namespace" {
  source = "../../modules/namespace"

  name        = local.namespace
  environment = local.environment
}

module "resources" {
  source = "../../modules/resources"

  namespace = module.namespace.name

  quota_pods   = "12"
  quota_cpu    = "2"
  quota_memory = "2Gi"

  default_request_cpu    = "50m"
  default_request_memory = "64Mi"
  default_limit_cpu      = "250m"
  default_limit_memory   = "128Mi"

  max_limit_cpu    = "1"
  max_limit_memory = "512Mi"
}

module "rbac" {
  source = "../../modules/rbac"

  namespace            = module.namespace.name
  service_account_name = "bituach-app"

  # Stateless HTTP services: the workload identity needs no API access of its
  # own. Granting none is the honest minimum, not an oversight.
  role_rules = []
}

# Developers can change things in dev. This is the RBAC difference that the
# environment topology documents: edit in dev, view in staging, none in prod.
resource "kubernetes_role_binding_v1" "developers_edit" {
  metadata {
    name      = "developers-edit"
    namespace = module.namespace.name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind     = "Group"
    name     = "bituach-developers"
    api_group = "rbac.authorization.k8s.io"
  }
}

module "networkpolicy" {
  source = "../../modules/networkpolicy"

  namespace = module.namespace.name

  # Dev pulls images from GHCR at runtime, so broader egress is allowed here.
  allow_internet_egress = true
}

# HPA is intentionally absent in dev: one replica, no autoscaling noise while
# iterating. Staging and prod enable it.
