# Platform layer

Cluster-wide components that are **not** part of any application environment.
They are installed once by `scripts/bootstrap.sh` and are shared by all three
namespaces (`bituach-dev`, `bituach-staging`, `bituach-prod`).

Everything here is a Helm values file. No manifests are hand-written: the chart
owns its own objects, and the values file is the reviewable artifact.

## What is installed and why

| Release | Namespace | Chart version | Role | Why this POC needs it |
|---|---|---|---|---|
| `ingress-nginx` | `ingress-nginx` | `4.15.1` | External entry point, TLS termination | The task asks for external customer-facing access over Ingress/LoadBalancer **with TLS**. One controller serves all three environments. |
| `metrics-server` | `kube-system` | `3.14.0` | Resource metrics API | `HorizontalPodAutoscaler` cannot compute utilisation without it. Docker Desktop does **not** ship it (verified: the `v1beta1.metrics.k8s.io` APIService is absent), so HPA would report `<unknown>`. |
| `argocd` | `argocd` | `10.18.0` (app `v3.6.1`) | GitOps reconciler | The task requires deployment to Kubernetes *via GitOps with Argo CD*. |
| `vault` | `vault` | `0.34.1` (app `2.0.4`) | Secret source of truth | The task requires Vault as the runtime secret backend. Runs in **dev mode** (in-memory, auto-unsealed) for the POC. |
| `external-secrets` | `external-secrets` | `2.15.0` | Vault → Kubernetes Secret sync | The task requires External Secrets Operator so secret values never appear in manifests, images, or code. |

Versions are pinned in `scripts/bootstrap.sh` and can be overridden per run
(e.g. `ARGOCD_CHART=10.19.0 ./scripts/bootstrap.sh`).

## Endpoints

| URL | Serves | TLS |
|---|---|---|
| `https://localhost` | default ingress response | self-signed |
| `https://argocd.localhost` | Argo CD UI | self-signed |
| `https://vault.localhost` | Vault UI | self-signed |
| `https://dev.bituach.localhost` | `engine`/`data`/`ingest` (dev) | self-signed |
| `https://staging.bituach.localhost` | staging | self-signed |
| `https://bituach.localhost` | production | self-signed |

`*.localhost` resolves to `127.0.0.1` in browsers. For `curl`, pin the address
explicitly:

```bash
curl -k --resolve argocd.localhost:443:127.0.0.1 https://argocd.localhost/
```

## Deliberate design choices

**TLS terminates at the ingress controller.** The Argo CD and Vault servers run
plain HTTP inside the cluster (`server.insecure: true` for Argo CD) because the
edge already encrypts. Terminating twice means two certificates to manage and a
redirect loop to debug for no benefit.

**One controller, three hosts.** A shared cluster for dev/staging/prod is the
locked decision for the POC (handoff.md §2, Q1). Separate ingress controllers
per environment would be the production answer, and `docs/environment-topology.md`
explains why.

**`injector` and `csi` are disabled in Vault.** Secrets reach pods through ESO,
not through Vault's own sidecar injector or CSI driver. Enabling both would give
two competing injection paths and confuse the demonstration of "no secrets in
manifests".

**Helm 4.** Both the Windows and WSL toolchains are on Helm 4.x; charts above
are Helm 3-compatible and install cleanly under Helm 4.

## What is *not* here (and why)

| Absent | Reason |
|---|---|
| Prometheus / Grafana / Alertmanager | Documented-only in the approved scope (handoff.md §3). `ServiceMonitor` is therefore disabled everywhere; `metrics` endpoints stay enabled so the documented design is one Helm release away. |
| cert-manager | The POC uses a locally generated self-signed certificate. Production uses cert-manager + Let's Encrypt; see `docs/architecture.md`. |
| Dex / SSO | Local Argo CD admin account only. SSO is a production concern. |
| Argo Rollouts | RollingUpdate is the declared strategy; canary/blue-green are documented evolutions (handoff.md §6). |

## Operations

```bash
# install or repair everything (idempotent)
./scripts/bootstrap.sh

# checkpoint report: does the platform actually work?
./scripts/verify.sh

# remove everything this POC created
./scripts/teardown.sh --yes
```

### Argo CD admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### Vault root token

Dev mode uses the static root token `root` (set in `vault.yaml`). It is a
development convenience, is not a committed secret, and is replaced by
Kubernetes-auth-backed short-lived tokens in the documented production design.
