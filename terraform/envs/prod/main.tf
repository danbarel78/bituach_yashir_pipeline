# bituach-prod - production environment.
#
# Values come from handoff.md §4:
#   replicas 2, CPU 200m/500m, memory 256Mi/512Mi, quota 24 pods / 6 CPU / 6Gi,
#   HPA min 2 / max 3 at 70% CPU, developers read-only, Argo CD only.
#
# This is the strictest of the three: no internet egress, no human write access,
# and Argo CD is the only thing that may change the workload state.

locals {
  environment = "prod"
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

  quota_pods   = "24"
  quota_cpu    = "6"
  quota_memory = "6Gi"

  default_request_cpu    = "200m"
  default_request_memory = "256Mi"
  default_limit_cpu      = "500m"
  default_limit_memory   = "512Mi"

  max_limit_cpu    = "1"
  max_limit_memory = "1Gi"
}

module "rbac" {
  source = "../../modules/rbac"

  namespace            = module.namespace.name
  service_account_name = "bituach-app"

  role_rules = []
}

# Read-only for humans. Nobody deploys to prod by hand: the GitOps commit is
# the only interface, and Argo CD holds the credentials.
resource "kubernetes_role_binding_v1" "developers_view" {
  metadata {
    name      = "developers-view"
    namespace = module.namespace.name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }

  subject {
    kind      = "Group"
    name      = "bituach-developers"
    api_group = "rbac.authorization.k8s.io"
  }
}

module "networkpolicy" {
  source = "../../modules/networkpolicy"

  namespace = module.namespace.name

  # Stricter than dev/staging: no internet egress at all. The workloads are
  # internal-only HTTP services; anything that needs the internet at runtime is
  # a design smell and should go through an explicit, reviewed allow rule.
  allow_internet_egress = false
}

module "hpa_engine" {
  source = "../../modules/autoscaling"

  namespace       = module.namespace.name
  name            = "engine-hpa"
  deployment_name = "engine"
  min_replicas    = 2
  max_replicas    = 3
}

module "hpa_data" {
  source = "../../modules/autoscaling"

  namespace       = module.namespace.name
  name            = "data-hpa"
  deployment_name = "data"
  min_replicas    = 2
  max_replicas    = 3
}

module "hpa_ingest" {
  source = "../../modules/autoscaling"

  namespace       = module.namespace.name
  name            = "ingest-hpa"
  deployment_name = "ingest"
  min_replicas    = 2
  max_replicas    = 3
}
