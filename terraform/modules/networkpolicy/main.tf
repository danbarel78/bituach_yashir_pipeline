# Default-deny for every pod in the namespace. NetworkPolicy is additive: with
# no other policy present, this blocks all ingress and all egress, and the
# allow-* policies below carve out exactly what is needed.
#
# This is verified, not just declared: Phase 2/5 exercise an allow (engine ->
# data) and a deny (data -> ingest) against the live cluster.
resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "${var.name_prefix}-default-deny-all"
    namespace = var.namespace
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]
  }
}

# The ingress controller must reach the app pods from outside the namespace.
resource "kubernetes_network_policy_v1" "allow_ingress_controller" {
  metadata {
    name      = "${var.name_prefix}-allow-ingress-controller"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = var.app_selector
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.ingress_namespace
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "8000"
      }
    }
  }
}

# Service-to-service traffic inside the namespace: engine -> data and
# engine -> ingest both resolve to ClusterIP Services on port 8000.
resource "kubernetes_network_policy_v1" "allow_intra_namespace" {
  metadata {
    name      = "${var.name_prefix}-allow-intra-namespace"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = var.app_selector
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {
          match_labels = var.app_selector
        }
      }

      ports {
        protocol = "TCP"
        port     = "8000"
      }
    }

    egress {
      to {
        pod_selector {
          match_labels = var.app_selector
        }
      }

      ports {
        protocol = "TCP"
        port     = "8000"
      }
    }
  }
}

# DNS must always resolve, otherwise nothing else works.
resource "kubernetes_network_policy_v1" "allow_dns_egress" {
  metadata {
    name      = "${var.name_prefix}-allow-dns-egress"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = var.app_selector
    }

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }

      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
  }
}

# Optional broader egress. Kept off in production: the workloads have no
# legitimate reason to call the internet at runtime, and allowing it silently
# would weaken the exfiltration story.
resource "kubernetes_network_policy_v1" "allow_internet_egress" {
  count = var.allow_internet_egress ? 1 : 0

  metadata {
    name      = "${var.name_prefix}-allow-internet-egress"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = var.app_selector
    }

    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
          except = [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
          ]
        }
      }
    }
  }
}
