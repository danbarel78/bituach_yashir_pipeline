# Modules

Reusable building blocks for an environment. Each module owns exactly one
concern so `envs/*` reads as a description of the environment rather than a
wall of Kubernetes objects.

| Module | Objects | Why Terraform, not GitOps |
|---|---|---|
| `namespace` | `Namespace` | Environments are infrastructure, not application state. |
| `resources` | `ResourceQuota`, `LimitRange` | Guard rails must exist before workloads land, and app teams should not be able to raise their own ceiling. |
| `rbac` | `ServiceAccount`, `Role`, `RoleBinding` | Permission grants are a platform decision, not an app commit. |
| `networkpolicy` | `NetworkPolicy` (default-deny + explicit allows) | Same reason as RBAC: the allow-list is a security boundary. |
| `autoscaling` | `HorizontalPodAutoscaler` (v2) | Scaling policy is an environment property that differs per environment. |

**Deliberate boundary (handoff.md §9):** application `Deployment`s, `Service`s
and `Ingress`es are **not** managed here. They live in `gitops/` and are
reconciled by Argo CD. Terraform and Argo CD would otherwise both claim the same
objects and fight over `replicas`, image tags, and labels.

Provider requirement: `hashicorp/kubernetes` >= 2.30.
