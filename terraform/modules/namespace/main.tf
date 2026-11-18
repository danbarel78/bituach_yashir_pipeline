resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.name

    labels = merge(
      {
        "app.kubernetes.io/part-of"          = "bituach-yashir"
        "bituach-yashir/environment"         = var.environment
        "pod-security.kubernetes.io/enforce" = var.pod_security_enforce
        "pod-security.kubernetes.io/audit"   = var.pod_security_enforce
        "pod-security.kubernetes.io/warn"    = var.pod_security_enforce
      },
      var.labels,
    )
  }
}
