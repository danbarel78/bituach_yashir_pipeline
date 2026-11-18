# Review & walkthrough — what exists today (P0–P3)

**Date:** 2026-11-18
**Purpose:** explain the current state of the POC in plain language, map it to the
assignment, prepare answers to likely questions, and give a hands-on guide.
**Scope:** everything built through Phase 3 plus the endpoint fixes. Phases 4–6
(Jenkins, runtime secrets, documentation/release) are **not built yet** — this
document says so explicitly wherever it matters.

Everything marked "verified" below was re-checked on the cluster on
2026-11-18: `scripts/verify.sh` **21/21**, production smoke **9/9**, all four
Argo CD applications **Synced/Healthy**.

---

## 1. Where the project stands

| Phase | Content | Status |
|---|---|---|
| P0 | Scaffold, version tooling, `main` + `develop` | ✅ done |
| P1 | Three FastAPI services, tests, Dockerfiles | ✅ done |
| P2 | Local cluster, ingress + TLS, Argo CD, Vault, ESO, scripts | ✅ done |
| P3 | Terraform (quota/RBAC/netpol/HPA), kustomize overlays, app-of-apps | ✅ done |
| — | Endpoint fixes (`/items`, `/ingest`) + per-service hostnames | ✅ done |
| — | Images published to public GHCR + overlays pinned by digest | ✅ done |
| P4 | Jenkins CI/CD pipeline | ⛔ not started |
| P5 | Vault → ESO → Pod secret path end-to-end | ⛔ components installed, path not wired |
| P6 | README, decisions doc, versioning docs, `v1.0.0` tag, CHANGELOG | ⛔ not started |

**One-sentence status for a manager:**
> The platform and the GitOps delivery loop are real and verified end-to-end;
> three services deploy to three isolated environments from Git. CI/CD and the
> secret-injection path are the next two phases, and the written deliverables
> come last.

> Note: `handoff.md` §3 describes the **target** end state of the whole
> assignment. This document describes what is actually running **today**.

---

## 2. What is running right now (verified)

### Services

| Service | Role | Internal dependency |
|---|---|---|
| `engine` | Orchestrator / entry point | calls `data` and `ingest` over ClusterIP DNS |
| `data` | Serves a small sample catalog (`/items`) | none |
| `ingest` | Accepts a payload and acknowledges it (`/ingest`) | none |

Live proof:

```json
GET https://engine.dev.bituach.localhost/version
{"service":"engine","version":"0.0.1-dev.0+11e3604","gitSha":"11e3604","environment":"dev"}

GET https://engine.dev.bituach.localhost/aggregate
{"service":"engine","downstream":[
  {"service":"data","reachable":true},
  {"service":"ingest","reachable":true}],"all_reachable":true}
```

The second response is the important one: it proves **service-to-service
communication inside the cluster** works over `ClusterIP` Services, not
`localhost` and not a mock.

### Environments

| | dev | staging | prod |
|---|---|---|---|
| Namespace | `bituach-dev` | `bituach-staging` | `bituach-prod` |
| Replicas per service | 1 | 2 | 2 |
| HPA | disabled | 2–3 @ 70% CPU | 2–3 @ 70% CPU |
| Argo CD sync | automatic | automatic | **manual** |
| External host | `dev.bituach.localhost` | `staging.bituach.localhost` | `bituach.localhost` |
| Per-service host | `engine.dev.…`, `data.dev.…`, `ingest.dev.…` | same pattern | `engine.bituach.localhost`, … |

Isolation is enforced by four separate mechanisms, all from Terraform:

- **ResourceQuota + LimitRange** — a namespace cannot starve the others.
- **RBAC** — developers `edit` in dev, `view` in staging, no access in prod.
- **NetworkPolicy** — default-deny, then explicit allow for DNS, intra-namespace
  traffic and the ingress controller.
- **Separate ServiceAccounts** — `bituach-app`, with no API permissions and no
  automounted token.

### The delivery loop

```
git push → Argo CD detects the new commit → renders gitops/overlays/<env>
        → applies to the cluster → probes decide when the pod is "ready"
```

There is no `kubectl apply` in the normal workflow. The only manual step is
prod's "Sync" button, which is the approval gate.

---

## 3. Requirement coverage (assignment → reality)

| Assignment requirement | Where it is implemented | Status today |
|---|---|---|
| Real local cluster, working POC, not mocked | Docker Desktop Kubernetes, 3 namespaces, live URLs | ✅ |
| Jenkins: build, tests, SAST/dependency + image scan, GitOps deploy | `ci/Jenkinsfile`, `ci/docker/jenkins/` | ⛔ **not built** (P4) |
| Version management: GitFlow, SemVer, tagging policy, changelog, rollout | `ci/scripts/version.py`, `scripts/release.sh`, `base_version.json`, `strategy.rollingUpdate`, digest-pinned overlays | ⚠️ SemVer engine + immutable digest pins done; docs, tags, CHANGELOG missing (P6) |
| Vault + ESO, no secrets in manifests/code/logs, CI-time + runtime | Vault and ESO installed; `ExternalSecret`/`ClusterSecretStore` not created | ⚠️ **components only** (P5) |
| Dev/staging/prod + justification + Terraform (quota, limits, RBAC, SA, netpol, HPA, replicas) | `terraform/modules/*`, `terraform/envs/*` | ✅ code written and applied; written justification still to do |
| Internal vs external channels + SLA/monitoring/alerting differences | Internal ClusterIP + Ingress/TLS implemented; monitoring stack designed only | ⚠️ implementation ✅, documentation ⛔ |
| README + one-page decisions doc | — | ⛔ **missing** |

Read this table as: **three of seven requirements are fully demonstrated**, two
are half done (design + partial implementation), two are not started.

---

## 4. Key concepts, in plain language

**1. A deployment is an address, not a file.**
Every image gets an immutable version (`1.2.0`) and eventually a digest
(`@sha256:…`). `latest` is banned because "which code is in production?" must
have exactly one answer. The `/version` endpoint answers that question from
inside the running pod: it returns the version and git SHA baked into the image
at build time (`0.0.1-dev.0+11e3604` above).

**2. Git is the source of truth; the cluster is a follower.**
Argo CD continuously compares the desired state in Git with the actual state in
the cluster. If they differ, that is called **drift**, and Argo CD can correct
it automatically (**self-heal**). This is what makes "the cluster was changed by
hand" a detectable, temporary condition instead of a permanent mystery.

**3. Same manifests, different environments.**
`gitops/base/` holds what never changes (probes, security context, ports,
rolling-update strategy). `gitops/overlays/<env>/` holds only what differs
(namespace, replicas, image tag, hostname, `ENVIRONMENT` value). That is why a
promotion is a two-line diff, and why dev can never accidentally carry prod's
hostname.

**4. Terraform and Kustomize do different jobs.**
Terraform owns the **platform contract**: namespaces, quotas, RBAC, service
accounts, NetworkPolicies, HPAs. Kustomize/Argo CD owns the **application
state**: Deployments, Services, Ingresses. Both are code; neither is a manual
step. Keeping the boundary sharp prevents two tools fighting over one object.

**5. Health is a contract, not a log line.**
- `/healthz` = "the process is alive" (liveness). Never checks dependencies,
  or a database blip would restart every pod for no reason.
- `/readyz` = "I can serve traffic" (readiness). Checks dependencies, so a pod
  is removed from the Service instead of returning errors.
- `startupProbe` gives a cold start up to 60 s before liveness starts counting.

**6. Zero-downtime rollout is a setting plus a probe.**
`maxSurge: 1`, `maxUnavailable: 0`: a new pod must exist and pass readiness
before an old one is removed. Capacity never dips below the desired count.

**7. Secrets should be referenced, never stored.**
Vault holds the value. External Secrets Operator copies it into a Kubernetes
Secret. The pod reads an environment variable. The value never appears in Git,
a manifest, an image layer or a log line. (Installed today; the wiring is P5.)

**8. Quality gates fail the build, they do not warn.**
`ruff`, `mypy --strict`, `pyright`, `pytest` with an 80% coverage floor,
`bandit`, `pip-audit`, Trivy. A warning that nobody reads is not a control.

**9. Rollback is a Git revert, not a kubectl command.**
Revert the overlay commit; Argo CD reconciles back to the previous digest. The
history of what was deployed, when and why stays reviewable.

---

## 5. The 90-second explanation for your manager

> "I took a real three-service Python application and built the delivery path
> around it. The services are containerised, non-root, with health probes and
> resource limits, and they talk to each other only through internal Kubernetes
> Services.
>
> The cluster has three isolated environments — dev, staging, production — in
> separate namespaces, each with its own CPU/memory quota, permissions and
> network rules. Those are created by Terraform, so they are reproducible.
>
> Deployment is GitOps: I change Git, Argo CD makes the cluster match. Nobody
> deploys by hand. If someone changes the cluster manually, Argo CD detects the
> drift and reverts it — I measured it at about two and a half seconds. Prod is
> the exception: it waits for a human to press Sync, which is our approval gate.
>
> Every image is tagged immutably, and each pod reports the version and commit
> it was built from, so 'what is running in prod?' is a one-command answer.
>
> What is still to come is the Jenkins pipeline that builds and scans the
> images automatically, and the Vault-to-pod secret path. The platform they plug
> into is already running and verified."

---

## 6. Likely questions and short answers

**Q: Why one cluster instead of separate clusters per environment?**
Cost and speed for a POC: one control plane, one ingress, easy to show
namespace-level isolation. Production recommendation is a separate cluster for
prod (blast radius, upgrade cadence, compliance boundary) and dev+staging
sharing one. The trade-off is written in the topology document.

**Q: Is namespace isolation really isolation?**
For quotas, RBAC and network traffic, yes — those are enforced by the API
server, the scheduler and the CNI respectively. It is not a security boundary
against a cluster-admin or a node-level compromise, which is exactly why prod
gets its own cluster in the production design.

**Q: Why GitFlow rather than trunk-based?**
The assignment asks for GitFlow, and it gives a clean audit trail: feature →
develop → release → main → tag. The tag is what prod deploys, so the release
artifact has a human-readable name and a permanent SHA.

**Q: Why is `latest` forbidden?**
It is mutable. Two nodes can run different code under the same tag, and
rollback becomes guesswork. We use `vX.Y.Z` plus digest pins; the digest is what
actually guarantees "the same bits everywhere".

**Q: How do you know what is deployed?**
`/version` on each service returns version, git SHA and environment, injected as
Docker build args. Argo CD also records the synced commit and the image digest in
its history.

**Q: How does rollback work?**
Revert the GitOps commit. Argo CD syncs the previous digest. It is deliberate,
reviewable and takes seconds — and it does not depend on remembering a kubectl
command at 3 a.m.

**Q: What happens if a bad image is pushed?**
Today: CI gates are designed (tests, coverage, bandit, pip-audit, Trivy) but the
pipeline is P4, and prod already requires manual Sync. When P4 lands, a
HIGH/CRITICAL finding fails the build before anything reaches an overlay.

**Q: Where do secrets live, and could they leak into Git?**
Vault is the source of truth; ESO copies values into Kubernetes Secrets;
workloads read environment variables. Nothing secret is committed — the TLS key
is generated locally at bootstrap and never added to Git. A gitleaks stage is
planned in P4. Runtime wiring is P5, so today this is a design, not a demo.

**Q: Single node, dev-mode Vault — isn't that fragile?**
Yes, deliberately. It is a POC on a laptop. Vault dev mode is in-memory and
auto-unsealed; the production path (Raft, auto-unseal, Kubernetes auth) is
documented. The point is to prove the mechanism, not to claim production
hardening.

**Q: Why Terraform *and* Kustomize? Isn't that duplication?**
They own different objects and different lifecycles. Terraform provisions the
guardrails (quota, RBAC, network policy, HPA); Kustomize describes the app that
lives inside them. Mixing both in one tool blurs "who may change this?".

**Q: How do you get zero-downtime deployments?**
`maxSurge: 1` / `maxUnavailable: 0` plus a readiness probe. A new pod must be
Ready before an old one is terminated.

**Q: What about monitoring and alerting?**
Probes are implemented and are the health signal. Prometheus/Grafana/Alertmanager
are deliberately out of scope for the "implement exactly the letter" decision;
the design (metrics, SLOs, alert rules, routing per environment) is written up
separately. `metrics-server` *is* installed because HPA is useless without it.

**Q: Why do all three environments currently track `develop`?**
So the POC can show three environments from one commit. Promotion wiring —
release branch for staging, tag for prod — is P4/P6 work and is called out as a
known follow-up rather than hidden.

**Q: How do you avoid two tools fighting over the same object?**
The boundary above, plus Argo CD's resource tracking and `ApplyOutOfSyncOnly`.
Terraform never touches Deployments; Argo CD never touches quotas or RBAC.

**Q: What would you do differently with more time?**
Separate prod cluster; Argo Rollouts canary with automated analysis; real
cert-manager certificates; private registry with pull secrets from ESO; full
observability stack. All are documented as the production evolution.

---

## 7. Hands-on guide

All cluster commands work in **PowerShell**. Scripts are bash — run them in
**WSL Ubuntu**. The repository path in WSL is:

```
/mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline
```

### 7.1 Check that the environment is alive

```powershell
docker version --format '{{.Server.Version}}'
kubectl get nodes
kubectl get applications -n argocd
```

Expected: Docker `29.8.2`, node `Ready`, and four applications
(`bituach-root`, `-dev`, `-staging`, `-prod`) all `Synced / Healthy`.

Full checkpoint (21 assertions):

```powershell
wsl -d Ubuntu -- bash -lc 'cd /mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline && ./scripts/verify.sh'
```

### 7.2 Run the services locally (no Kubernetes)

One service — the fastest loop:

```powershell
cd services\engine
uv sync --extra dev
uv run uvicorn engine.main:app --reload --port 8000
```

Then open <http://localhost:8000/docs> (interactive OpenAPI) and try:

```powershell
curl.exe http://localhost:8000/
curl.exe http://localhost:8000/healthz
curl.exe http://localhost:8000/version
```

`/readyz` will return 503 locally, on purpose: it checks the two downstream
services, which are not running. To run the full trio, use three terminals:

```powershell
# terminal 1 — data
cd services\data;      uv run uvicorn data.main:app   --port 8001
# terminal 2 — ingest
cd services\ingest;    uv run uvicorn ingest.main:app --port 8002
# terminal 3 — engine, pointed at the local peers
cd services\engine
$env:DATA_SERVICE_URL   = "http://localhost:8001"
$env:INGEST_SERVICE_URL = "http://localhost:8002"
uv run uvicorn engine.main:app --port 8000
```

Now `/readyz` is 200 and `/aggregate` shows `all_reachable: true`.

Tests and quality gates (per service, from its directory):

```powershell
uv run pytest -q
uv run ruff check .
uv run mypy src
```

### 7.3 Open the Argo CD UI

Browser: <https://argocd.localhost> — Chrome and Edge resolve `*.localhost` to
`127.0.0.1`. Accept the self-signed certificate warning.

If the browser refuses to resolve it, use a port-forward instead:

```powershell
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

then open <http://localhost:8080>.

Credentials:

```powershell
# username
admin
# password
kubectl -n argocd get secret argocd-initial-admin-secret `
  -o jsonpath='{.data.password}' | ForEach-Object {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_))
  }
```

What to look at, in order:

1. **Applications** — four cards. `bituach-root` is the app-of-apps; the other
   three are environments.
2. Click **bituach-dev** → the resource tree (Deployments → ReplicaSets → Pods,
   Services, Ingress). This is the live picture of the namespace.
3. **Diff** tab — Git desired state vs cluster actual state. Empty diff = Synced.
4. **History and Rollback** — every synced commit and its images.
5. `bituach-prod` has no automated sync policy: it is the approval gate.

### 7.4 See what is deployed (command line)

```powershell
kubectl get deploy,pods -n bituach-prod -o wide
kubectl get hpa,resourcequota,networkpolicy -n bituach-prod
kubectl get ingress -A
```

Talk to the services through the real external path (ingress → Service → pod):

```powershell
curl.exe -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 https://engine.dev.bituach.localhost/
curl.exe -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 https://engine.dev.bituach.localhost/aggregate
curl.exe -sk --resolve data.dev.bituach.localhost:443:127.0.0.1 https://data.dev.bituach.localhost/items
curl.exe -sk --resolve ingest.bituach.localhost:443:127.0.0.1 -X POST https://ingest.bituach.localhost/ingest -H "Content-Type: application/json" -d '{\"source\":\"demo\",\"payload\":{\"claim\":123}}'
```

`--resolve` is needed because Windows does not resolve `*.localhost`; the browser
does. The `-k` accepts the self-signed certificate.

Run the pipeline's own post-deploy gate:

```powershell
wsl -d Ubuntu -- bash -lc 'cd /mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline && ./scripts/smoke-test.sh --env dev'
```

### 7.5 Demonstrate drift and self-heal (the money shot)

Terminal 1 — watch:

```powershell
kubectl -n bituach-dev get deploy data -w
```

Terminal 2 — break the desired state by hand:

```powershell
kubectl -n bituach-dev scale deploy/data --replicas=4
```

What happens: the Deployment briefly says `4`, Argo CD notices the object no
longer matches Git, and reverts it to `1`. **Measured today: about 2.5 seconds.**
The UI shows the app return to `Synced`; the Argo CD application events record
the self-heal.

A second variant, closer to a real incident — change a value instead of a count:

```powershell
kubectl -n bituach-dev set env deploy/engine DEMO_DRIFT=1
kubectl -n bituach-dev get deploy engine -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'
# after a few seconds DEMO_DRIFT is gone again
```

To prove prod is *not* self-healing (the approval gate), do the same in
`bituach-prod`: it stays `OutOfSync` until you press **Sync** in the UI. Restore
it the same way — Sync — so you leave the cluster clean.

> Note: this is safe and reversible. Nothing is lost; Argo CD's job is exactly
> this.

### 7.6 Watch a deployment happen

```powershell
# after the image tag in an overlay changes and Argo CD syncs:
kubectl -n bituach-dev rollout status deploy/engine
kubectl -n bituach-dev get pods -l app.kubernetes.io/name=engine -w
```

During a rollout you should always see the desired number of Ready pods —
`maxUnavailable: 0` guarantees a new pod is Ready before an old one leaves.

Logs (structured JSON, no request bodies, no secrets):

```powershell
kubectl -n bituach-prod logs deploy/engine --tail=20
kubectl -n bituach-prod logs deploy/engine --tail=50 | Select-String '"level":"ERROR"'
```

### 7.7 Rebuild and redeploy an image

The overlays pin **digests** (`ghcr.io/...@sha256:…`), so a rebuilt image is not
picked up by re-tagging. The intended path is: build → push a new immutable tag
to GHCR → pin the new digest in the overlay → commit/push → Argo CD syncs.

```powershell
docker build --build-arg APP_VERSION=0.0.1-dev.0 --build-arg GIT_SHA=$(git rev-parse --short HEAD) `
  -t ghcr.io/danbarel78/bituach-yashir-engine:0.0.1-dev.0-<sha> services/engine
docker push ghcr.io/danbarel78/bituach-yashir-engine:0.0.1-dev.0-<sha>
docker buildx imagetools inspect ghcr.io/danbarel78/bituach-yashir-engine:0.0.1-dev.0-<sha>
# put the new sha256 digest in gitops/overlays/dev/kustomization.yaml, commit, push
```

Local fallback (no registry round-trip, useful while iterating): build the
`:local` tag, import it into the node, and temporarily override the overlay —
but remember the committed state must stay a digest for reproducibility.

```powershell
docker build -t ghcr.io/danbarel78/bituach-yashir-engine:local services/engine
```

The image must be imported into the node's containerd — `docker build` alone is
not enough, because the node has a separate image store:

```powershell
# recommended: enable Docker Desktop > Settings > Resources > WSL Integration
wsl -d Ubuntu -- bash -lc 'cd /mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline && ./scripts/load-images.sh engine'
```

Then force the pods to pick it up:

```powershell
kubectl -n bituach-dev rollout restart deploy/engine
```

### 7.8 Shut it all down

```powershell
wsl -d Ubuntu -- bash -lc 'cd /mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline && ./scripts/teardown.sh --yes'
```

This removes the platform releases and the three environment namespaces. The
repository is untouched, so `./scripts/bootstrap.sh` + Terraform bring it back.

---

## 8. Cheat sheet

| What | Command / URL |
|---|---|
| Argo CD UI | <https://argocd.localhost> (admin + secret password) |
| Vault UI | <https://vault.localhost> (token `root`, dev mode) |
| dev / staging / prod | `https://dev.bituach.localhost`, `…staging…`, `https://bituach.localhost` |
| Per-service hosts | `engine.dev.bituach.localhost`, `data.dev…`, `ingest.dev…` (same per env) |
| App status | `kubectl get applications -n argocd` |
| Env status | `kubectl get deploy,pods,hpa -n bituach-prod` |
| Platform check | `./scripts/verify.sh` (WSL) |
| Post-deploy check | `./scripts/smoke-test.sh --env <env>` (WSL) |
| Version logic | `python ci/scripts/version.py` |
| Drift demo | `kubectl -n bituach-dev scale deploy/data --replicas=4` |
| Logs | `kubectl -n <ns> logs deploy/<svc> --tail=50` |
| Ingress hosts | `kubectl get ingress -A` |

---

## 9. Gaps to close before submission

Ordered by importance to the assignment:

1. **Jenkins pipeline (P4)** — the assignment names it explicitly; currently
   absent. Needs the controller image, `Jenkinsfile`, scan script, PAT for GHCR.
2. **Runtime secrets (P5)** — `ClusterSecretStore` + `ExternalSecret` per
   namespace, consumed by the pods, plus the rotation demo. Components are
   installed; nothing is wired.
3. **Deliverable docs (P6)** — `README.md` (how to run/test) and
   `docs/decisions.md` (one page) are required deliverables and **do not exist
   yet**. Same for `docs/versioning.md`, `git-workflow.md`, `environment-topology.md`,
   `observability-design.md`, `secrets.md`, `runbook.md`, `architecture.md`.
4. **Promotion wiring** — all apps track `develop`; staging should track the
   release branch, prod the tag.
5. **Release artifacts** — no `CHANGELOG.md`, no `v1.0.0` tag, no real release
   run of `scripts/release.sh`.

Items 1–3 are the ones a reviewer will notice first.