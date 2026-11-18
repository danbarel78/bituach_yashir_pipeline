# bituach-staging - pre-production environment.
#
# Values come from handoff.md §4:
#   replicas 2, CPU 100m/500m, memory 128Mi/256Mi, quota 20 pods / 4 CPU / 4Gi,
#   HPA min 2 / max 3 at 70% CPU, developers read-only, CI may deploy.

locals {
  environment = "staging"
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

  quota_pods   = "20"
  quota_cpu    = "4"
  quota_memory = "4Gi"

  default_request_cpu    = "100m"
  default_request_memory = "128Mi"
  default_limit_cpu      = "500m"
  default_limit_memory   = "256Mi"

  max_limit_cpu    = "1"
  max_limit_memory = "1Gi"
}

module "rbac" {
  source = "../../modules/rbac"

  namespace            = module.namespace.name
  service_account_name = "bituach-app"

  # Same minimum-privilege workload identity as dev: no API access needed.
  role_rules = []
}

# Developers can look but not touch in staging; the pipeline does the writing.
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

# CI (Jenkins) needs to deploy into staging, so it gets edit here - but not in
# prod, where only Argo CD reconciles.
resource "kubernetes_role_binding_v1" "ci_edit" {
  metadata {
    name      = "ci-edit"
    namespace = module.namespace.name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "jenkins"
    namespace = "jenkins"
  }
}

module "networkpolicy" {
  source = "../../modules/networkpolicy"

  namespace = module.namespace.name

  # Staging still pulls images at runtime, so broader egress remains allowed.
  allow_internet_egress = true
}

# Autoscaling is enabled from staging onwards: min 2 keeps a rolling update from
# causing an outage, max 3 fits the single-node cluster.
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
