# ResourceQuota: the namespace-wide ceiling. Without it a single runaway
# deployment can starve every other workload on this single-node cluster.
resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "bituach-quota"
    namespace = var.namespace
  }

  spec {
    hard = {
      "pods"           = var.quota_pods
      "requests.cpu"   = var.quota_cpu
      "requests.memory" = var.quota_memory
      "limits.cpu"     = var.quota_cpu
      "limits.memory"  = var.quota_memory
    }
  }
}

# LimitRange: per-container defaults and caps. The defaults mean a manifest that
# forgets requests/limits still gets sane values instead of being rejected by
# the quota (a pod with no requests counts as zero and is easy to strand).
resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "bituach-limits"
    namespace = var.namespace
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = var.default_limit_cpu
        memory = var.default_limit_memory
      }

      default_request = {
        cpu    = var.default_request_cpu
        memory = var.default_request_memory
      }

      max = {
        cpu    = var.max_limit_cpu
        memory = var.max_limit_memory
      }
    }
  }
}
