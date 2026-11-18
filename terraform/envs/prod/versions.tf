terraform {
  required_version = ">= 1.6"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }

  # Local state is deliberate for this POC (handoff.md §9). Production uses a
  # remote backend with locking - documented in docs/environment-topology.md.
}
