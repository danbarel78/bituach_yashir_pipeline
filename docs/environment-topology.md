# Environment topology — dev, staging, production

This document answers the environment-topology part of the assignment:

- the Dev / Staging / Production layout,
- the choice between **namespaces in one cluster** and **separate clusters**,
  with the trade-offs,
- the Terraform IaC that makes the environments differ (ResourceQuota,
  requests/limits, RBAC, ServiceAccounts, NetworkPolicies, HPA, replicas).

The code is the source of truth: `terraform/envs/{dev,staging,prod}` and
`terraform/modules/*`. This document explains why it looks the way it does and
what is deliberately absent.

## 1. Topology as deployed

```
                    ┌───────────────────────────────────────────────┐
                    │ Docker Desktop Kubernetes — one node          │
                    │ control plane: desktop-control-plane          │
                    │                                               │
  ingress-nginx ────┤  namespace bituach-dev                        │
  (TLS, *.localhost)│    engine ×1   data ×1   ingest ×1            │
        │           │    quota 12 pods / 2 CPU / 2Gi                │
        │           │    HPA: none                                  │
        │           │                                               │
        ├──────────►│  namespace bituach-staging                    │
        │           │    engine ×2   data ×2   ingest ×2            │
        │           │    quota 20 pods / 4 CPU / 4Gi                │
        │           │    HPA: 2–3 @ 70% CPU                         │
        │           │                                               │
        └──────────►│  namespace bituach-prod                       │
                    │    engine ×2   data ×2   ingest ×2            │
                    │    quota 24 pods / 6 CPU / 6Gi                │
                    │    HPA: 2–3 @ 70% CPU                         │
                    └───────────────────────────────────────────────┘

  shared platform (cluster-scoped, installed once):
    argocd            — reconciles all three namespaces
    vault (dev mode)  — secret source
    external-secrets  — Vault → Kubernetes Secret
    metrics-server    — HPA metrics
```

One control plane, one ingress controller, one Argo CD, one Vault. The
environments are separated by four independent mechanisms, all created by
Terraform: ResourceQuota + LimitRange, RBAC, NetworkPolicy, and a dedicated
ServiceAccount per namespace.

## 2. Decision: namespaces in a shared cluster

### 2.1 What was chosen

**POC (deployed):** three namespaces — `bituach-dev`, `bituach-staging`,
`bituach-prod` — in the single Docker Desktop cluster.

**Production recommendation (documented):** a separate cluster for production;
dev and staging may continue to share one.

### 2.2 Comparison

| Criterion | Namespaces, shared cluster (chosen for POC) | Separate cluster per environment |
|---|---|---|
| Cost | One control plane, one node | 3× control plane, nodes and platform add-ons |
| Setup time | Minutes; already installed | Provision, bootstrap, certificate, DNS per cluster |
| Blast radius of a cluster-scoped mistake | **All environments** (CRD, webhook, RBAC, node pressure, control-plane upgrade) | Contained to one environment |
| Noisy neighbour | Contained by quota/limits, but the node is shared | Hard isolation |
| Kubernetes version upgrades | One upgrade affects all three at once | Upgrade dev first, then staging, then prod |
| RBAC boundary | Namespace-scoped for humans; cluster-admin sees everything | Genuine API-server boundary |
| Network isolation | NetworkPolicy only (same pod CIDR) | Separate networks; explicit peering required |
| Compliance / data residency | Difficult to defend for prod | Straightforward to scope |
| Secrets isolation | Vault policies + namespaces; same etcd | Separate etcd and Vault |
| Operational overhead | Lowest | Highest (3× everything) |
| Fidelity to production | Medium | High |

### 2.3 Justification

For the assignment's POC, namespaces win:

- The task asks to demonstrate isolation *and* the Terraform constructs that
  create it. Namespaces make all of them visible in one `kubectl get` and one
  Argo CD instance.
- A single-node laptop cluster cannot host three control planes. Pretending
  otherwise would add cost and setup time without adding a real boundary.
- Dev/staging/prod differ in **policy** (quota, RBAC, network, replicas), and
  those differences are exactly what the Terraform example must show. They are
  fully expressible at namespace scope.
- Promotion is tested end-to-end from one cluster: dev and staging auto-sync,
  prod waits for manual approval. The approval gate is a stronger demonstration
  than a second cluster would be. (All three Applications currently track
  `develop` so the POC can show three environments from one commit; wiring
  staging to `release/*` and prod to a tag is a known follow-up, recorded in
  `handoff.md` §20.)

What a namespace does **not** buy, stated plainly:

- It is not a security boundary against a cluster-admin or a node compromise.
- A cluster-scoped CRD, admission webhook or control-plane upgrade affects every
  environment.
- A node-level resource exhaustion affects all three namespaces regardless of
  quota.

Those are the reasons a real production estate puts prod in its own cluster.
The recommended evolution is:

| Stage | Topology |
|---|---|
| Today (POC) | 1 cluster, 3 namespaces |
| Near term | 1 shared cluster for dev+staging, 1 production cluster |
| Mature | 1 cluster per environment, or prod per region/tenant, with remote Terraform state and a cluster API |

A middle option — one cluster per environment but a shared platform cluster for
Argo CD/Vault — is possible; it adds cross-cluster credential management, which
is not justified at POC scale.

## 3. Environment matrix

Values below are the ones Terraform applies. The overlay column is the kustomize
side, which only carries what belongs to the application.

| Property | dev | staging | prod |
|---|---|---|---|
| Namespace | `bituach-dev` | `bituach-staging` | `bituach-prod` |
| Replicas per service (overlay) | 1 | 2 | 2 |
| CPU request / limit | 50m / 250m | 100m / 500m | 200m / 500m |
| Memory request / limit | 64Mi / 128Mi | 128Mi / 256Mi | 256Mi / 512Mi |
| LimitRange default request | 50m / 64Mi | 100m / 128Mi | 200m / 256Mi |
| LimitRange default limit | 250m / 128Mi | 500m / 256Mi | 500m / 512Mi |
| LimitRange max per container | 1 CPU / 512Mi | 1 CPU / 1Gi | 1 CPU / 1Gi |
| ResourceQuota | 12 pods, 2 CPU, 2Gi | 20 pods, 4 CPU, 4Gi | 24 pods, 6 CPU, 6Gi |
| HPA | none | 2–3 @ 70% CPU per service | 2–3 @ 70% CPU per service |
| Human RBAC | group `bituach-developers` → `edit` | `view` | `view` |
| CI RBAC | — | SA `jenkins` in ns `jenkins` → `edit` | none (Argo CD only) |
| Workload ServiceAccount | `bituach-app`, no token, no permissions | same | same |
| NetworkPolicy | default-deny + allows + internet egress | default-deny + allows + internet egress | default-deny + allows, **no internet egress** |
| Pod Security admission label | `baseline` (module default) | `baseline` | `baseline` |
| Argo CD sync | automated, prune, self-heal | automated, prune, self-heal | **manual** |
| External host | `engine.dev.bituach.localhost` (etc.) + `dev.bituach.localhost/<svc>/` | `engine.staging.bituach.localhost` + `staging.bituach.localhost/<svc>/` | `engine.bituach.localhost` + `bituach.localhost/<svc>/` |
| TLS | self-signed, all environments | self-signed | self-signed |

The replica and resource values live in the overlay, because Argo CD owns the
Deployment; the quota, RBAC, network and HPA values live in Terraform, because
those are platform guard rails. The split is explained in §6.

## 4. Terraform layout

```
terraform/
  modules/
    namespace/      Namespace + Pod Security labels
    resources/      ResourceQuota + LimitRange
    rbac/           ServiceAccount (+ optional Role/RoleBinding)
    networkpolicy/  default-deny + DNS + intra-namespace + ingress + optional egress
    autoscaling/    HorizontalPodAutoscaler v2 (CPU)
  envs/
    dev/            composition of the modules with dev values
    staging/        same modules, staging values
    prod/           same modules, prod values
```

Each environment is a root module with its own local state. The same modules
are used three times; only variables differ. That is what makes "environment
differences" reviewable as a small diff instead of three unrelated copies.

Provider and state (from `terraform/envs/*/versions.tf`):

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
  }
  # Local state is deliberate for the POC. Production uses a remote backend
  # (S3/GCS + locking) so the state is shared, encrypted and auditable.
}
```

### 4.1 Environment composition — `envs/dev/main.tf`

```hcl
locals {
  environment = "dev"
  namespace   = "bituach-${local.environment}"
  services    = ["engine", "data", "ingest"]
}

module "namespace" {
  source      = "../../modules/namespace"
  name        = local.namespace
  environment = local.environment
}

module "resources" {
  source    = "../../modules/resources"
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
  source               = "../../modules/rbac"
  namespace            = module.namespace.name
  service_account_name = "bituach-app"
  role_rules           = []          # workload needs no Kubernetes API access
}

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
    kind      = "Group"
    name      = "bituach-developers"
    api_group = "rbac.authorization.k8s.io"
  }
}

module "networkpolicy" {
  source                = "../../modules/networkpolicy"
  namespace             = module.namespace.name
  allow_internet_egress = true       # dev may pull/update from the internet
}
# No HPA module: one replica, no autoscaling noise while iterating.
```

### 4.2 What changes in staging and prod

| Module / object | dev | staging | prod |
|---|---|---|---|
| `resources` arguments | 12 / 2 / 2Gi | 20 / 4 / 4Gi | 24 / 6 / 6Gi |
| Human binding | `developers-edit` → `edit` | `developers-view` → `view` | `developers-view` → `view` |
| CI binding | — | `ci-edit` (SA `jenkins` in ns `jenkins`) | — |
| `networkpolicy.allow_internet_egress` | `true` | `true` | **`false`** |
| `hpa_engine`, `hpa_data`, `hpa_ingest` | absent | min 2 / max 3 @ 70% | min 2 / max 3 @ 70% |

Production is the strictest environment: no human write access, no internet
egress, and the only deployment path is Argo CD's manual sync.

### 4.3 The modules

**ResourceQuota** (`modules/resources/main.tf`) — the namespace ceiling:

```hcl
resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "bituach-quota"
    namespace = var.namespace
  }
  spec {
    hard = {
      "pods"            = var.quota_pods
      "requests.cpu"    = var.quota_cpu
      "requests.memory" = var.quota_memory
      "limits.cpu"      = var.quota_cpu
      "limits.memory"   = var.quota_memory
    }
  }
}
```

**LimitRange** — defaults and caps per container:

```hcl
resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "bituach-limits"
    namespace = var.namespace
  }
  spec {
    limit {
      type            = "Container"
      default         = { cpu = var.default_limit_cpu, memory = var.default_limit_memory }
      default_request = { cpu = var.default_request_cpu, memory = var.default_request_memory }
      max             = { cpu = var.max_limit_cpu, memory = var.max_limit_memory }
    }
  }
}
```

The two objects solve different failures: the quota stops a namespace from
starving the cluster, and the LimitRange stops a manifest that forgets
requests/limits from landing as a zero-request pod. The `max` also prevents one
container from consuming the whole namespace quota.

**ServiceAccount and RBAC** (`modules/rbac/main.tf`):

```hcl
resource "kubernetes_service_account_v1" "app" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
  }
  automount_service_account_token = false
}
```

The Role and RoleBinding are created only when `role_rules` is non-empty. These
services are stateless HTTP servers; giving them API permissions would be a
bigger risk than the one it solves. The result is an identity that exists (so
the pod is not the shared `default` account) but has no permissions and no
mounted token.

**NetworkPolicy** (`modules/networkpolicy/main.tf`):

| Policy | Effect |
|---|---|
| `bituach-default-deny-all` | selects every pod; denies all ingress and egress |
| `bituach-allow-ingress-controller` | ingress to port 8000 from namespace `ingress-nginx` |
| `bituach-allow-intra-namespace` | ingress+egress on port 8000 between pods with the app label |
| `bituach-allow-dns-egress` | UDP/TCP 53 to `kube-system` |
| `bituach-allow-internet-egress` | optional; denies RFC1918 destinations; **off in prod** |

NetworkPolicy is additive, so "default deny" plus explicit allows is the only
shape that produces a real allow-list. The deny is not theoretical: the
`engine → data` allow and the `data → ingest` deny were exercised against the
live cluster during platform verification (recorded in `handoff.md` §2).

**HPA** (`modules/autoscaling/main.tf`):

```hcl
resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }
  spec {
    min_replicas = var.min_replicas      # 2: a rolling update must not drop below capacity
    max_replicas = var.max_replicas      # 3: single-node cluster
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = var.deployment_name
    }
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}
```

`metrics-server` is a hard dependency and is installed by `scripts/bootstrap.sh`
because Docker Desktop does not ship it. Without it the HPA reports `<unknown>`
and never scales.

### 4.4 Sizing check (why the numbers are what they are)

Steady state, six or three pods:

| Environment | Pods | CPU requests | CPU limits | Memory requests | Memory limits |
|---|---|---|---|---|---|
| dev | 3 × 1 | 150m | 750m | 192Mi | 384Mi |
| staging | 3 × 2 | 600m | 3 CPU | 768Mi | 1.5Gi |
| prod | 3 × 2 | 1.2 CPU | 3 CPU | 1.5Gi | 3Gi |

Against the quota, the ceiling binds before the HPA's per-service maximum in one
case: staging allows 4 CPU of container limits, and nine pods at 500m (three
services × HPA max 3) would need 4.5 CPU. The quota is the real cap, so staging
saturates at eight 500m pods. This is acceptable on a single node — the quota is
the backstop that protects the other environments — but if staging is expected
to reach every HPA maximum simultaneously, raise `quota_cpu` to `5` or lower the
CPU limit to `400m`. Prod has 6 CPU of headroom, which covers nine pods plus one
surge pod per service exactly (12 × 500m = 6 CPU).

## 5. Application side: replicas and resources in the overlays

Terraform does not own Deployments, so replica counts and requests/limits are
set in `gitops/overlays/<env>/kustomization.yaml`:

```yaml
# prod
replicas:
  - { name: engine, count: 2 }
  - { name: data,   count: 2 }
  - { name: ingest, count: 2 }

patches:
  - target:
      kind: Deployment
      labelSelector: app.kubernetes.io/part-of=bituach-yashir
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: 200m
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: 500m
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: 256Mi
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: 512Mi
```

One patch targets every Deployment through the shared `part-of` label, so a new
service inherits the environment profile without a per-service copy. The
LimitRange is the safety net if an overlay ever forgets.

## 6. Boundary: Terraform versus GitOps

| Owned by Terraform (platform contract) | Owned by Argo CD / kustomize (application state) |
|---|---|
| Namespace and Pod Security labels | Deployment, ReplicaSet, Pod |
| ResourceQuota, LimitRange | Service, Ingress, TLS reference |
| ServiceAccount, Role, RoleBinding | ConfigMap (`ENVIRONMENT`) |
| NetworkPolicy | Image digest, replica count, resource patch |
| HorizontalPodAutoscaler | Argo CD Application sync policy |

Why not put everything in one tool:

- If Terraform owned `replicas`, every Argo CD HPA-driven scale or self-heal
  would show as drift and Terraform would fight the controller.
- If Argo CD owned RBAC and quotas, an application commit could raise its own
  ceiling — a permission decision disguised as a deploy.

The rule is: **guard rails are infrastructure, workloads are application
state.** `terraform/modules/README.md` states the same boundary.

Consequence to be honest about: Argo CD's own permissions are not managed by
this Terraform. It is installed by Helm with cluster-scoped access, which is why
prod needs no explicit binding for it. A production setup would scope Argo CD
with its own AppProject destinations and a dedicated cluster role.

## 7. How to add or change an environment

1. Copy `terraform/envs/<env>` to `terraform/envs/<new-env>`.
2. Change `locals.environment`, the quota/limit values, the RBAC bindings and
   whether the HPA modules exist.
3. `terraform init && terraform plan && terraform apply` from that directory.
4. Add `gitops/overlays/<new-env>/` with the namespace, digest pins, replica
   count and resource patch.
5. Add an `Application` in `gitops/argocd/apps/<new-env>.yaml`; the root
   app-of-apps picks it up if the directory is included.
6. Add the host names to the ingress list and to the TLS certificate SANs
   (`scripts/gen-self-signed-cert.sh`).
7. Add the environment to `scripts/smoke-test.sh` and the host map in
   `handoff.md`.

No module change is required — that is the test of whether the abstraction is
right.

## 8. Known limitations

| Limitation | Consequence | Production fix |
|---|---|---|
| Single node, single cluster | Node failure takes every environment down | Multi-node; separate prod cluster |
| Local Terraform state | No locking, state not shared | Remote backend with locking |
| Pod Security `baseline`, not `restricted` | Some hardening profiles are not enforced | Move to `restricted` once images/volumes comply |
| Shared Vault (dev mode) | Prod secrets share a process with dev | Dedicated Vault per environment, Raft storage |
| Argo CD cluster-scoped by default | It can change anything | AppProject restrictions, per-environment Argo CD |
| No PodDisruptionBudget / anti-affinity | A node drain can take all replicas | PDB + topology spread constraints |
| Quota caps HPA in staging | Max replicas may not all be schedulable | Raise quota or lower limits (§4.4) |

These are the same trade-offs recorded in `handoff.md` §16; they are inherent
to a laptop POC, not oversights in the Terraform.
