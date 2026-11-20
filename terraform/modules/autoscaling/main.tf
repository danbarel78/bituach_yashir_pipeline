# autoscaling/v2 HPA. Requires metrics-server, which scripts/bootstrap.sh
# installs into kube-system (Docker Desktop does not ship it).
resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    scale_target_ref {
      api_version = var.api_version
      kind        = var.target_kind
      name        = var.deployment_name
    }

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = var.cpu_utilization
        }
      }
    }
  }
}
