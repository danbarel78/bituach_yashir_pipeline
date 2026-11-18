# Workload identity. The Deployment references this account by name, so the pod
# gets exactly the permissions granted below and nothing from the default SA.
resource "kubernetes_service_account_v1" "app" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/part-of" = "bituach-yashir"
    }
  }

  # Public GHCR packages need no imagePullSecret. A private registry would add
  # one here, sourced from External Secrets - documented in docs/secrets.md.
  automount_service_account_token = false
}

# A Role with zero rules is invalid in Kubernetes ("at least 1 rule block is
# required"), and inventing a dummy permission to satisfy the schema would be
# worse than the problem. These stateless services need no API access, so no
# Role is created at all - an identity without permissions.
resource "kubernetes_role_v1" "app" {
  count = length(var.role_rules) > 0 ? 1 : 0

  metadata {
    name      = var.role_name
    namespace = var.namespace
  }

  dynamic "rule" {
    for_each = var.role_rules
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = rule.value.verbs
    }
  }
}

resource "kubernetes_role_binding_v1" "app" {
  count = length(var.role_rules) > 0 ? 1 : 0

  metadata {
    name      = var.role_name
    namespace = var.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.app[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.app.metadata[0].name
    namespace = var.namespace
  }

  dynamic "subject" {
    for_each = var.additional_subjects
    content {
      kind      = subject.value.kind
      name      = subject.value.name
      namespace = try(subject.value.namespace, null)
    }
  }
}
