# handoff.md — Bituach Yashir DevOps Assignment

**Project:** `danbarel78/bituach_yashir_pipeline`
**Document status:** Confirmed & approved scope baseline (Part 1 only)
**Created:** 2026-11-17
**Update cadence:** rewritten at the end of every major milestone / completed item
**Purpose:** single source of truth for what was agreed, what gets built, what gets documented, and what remains open — so work can resume after any interruption without re-deriving decisions.

---

## 0. How to use this document

- Sections 1–16 are the **approved baseline**. Changing them requires an explicit decision from the user.
- Section 17 lists **open items**; Section 18 is the **milestone log** (append-only, newest at the bottom).
- Section 19 records the **environment as observed**, so assumptions about the machine are not re-guessed.
- This file lives at the repository root and is committed (first build commit, 2026-11-18).

---

## 1. Assignment scope

Source: Home Assignment — Team Lead, DevOps & DevEx. The assignment has three parts; **only Part 1 is in scope now**. Parts 2 and 3 will be supplied by the user after Part 1 is finished and are out of scope for this document.

**Part 1 requirements (verbatim obligations):**

| Requirement | Verb → obligation |
|---|---|
| Choose an example repo and run it against a local cluster (Docker Desktop / Minikube / kind / k3d) as a working POC, not a mocked pipeline | Implement |
| Jenkins CI/CD pipeline: Docker image build, automated tests, basic security scanning (SAST/dependency + image vulnerability, e.g. Trivy), deployment to Kubernetes via GitOps with ArgoCD | Implement |
| Version-management strategy: branching (GitFlow), Semantic Versioning, container image tagging policy (immutable vs `latest`), changelog management, Kubernetes rollout strategy (Rolling Update / Blue-Green / Canary) | Define & document |
| Secrets management via Vault + External Secrets Operator; secure injection into Pods without exposing them in manifests, source code or logs; address CI/CD-time and runtime secrets | Design & demonstrate (working) |
| Environment topology Dev/Staging/Prod; justify namespaces-in-shared-cluster vs separate clusters; Terraform IaC example showing ResourceQuotas, Requests/Limits, RBAC, Service Accounts, NetworkPolicies, HPA/Autoscaling, replica counts | Design + Terraform code example |
| Explain support for internal channels (internal Services / ClusterIP) and external customer-facing channels (Ingress/LoadBalancer + TLS), including differences in SLA, monitoring/observability (Prometheus/Grafana, Liveness/Readiness probes) and alerting | Explain (documentation) |
| Deliverables: repo/archive with working code + README (how to run and test), one-page document with decisions, alternatives considered and trade-offs | Deliver |

---

## 2. Locked decisions

| # | Decision | Alternatives rejected | Rationale |
|---|---|---|---|
| Q1 | Docker Desktop Kubernetes, single node, single cluster, 3 namespaces (`bituach-dev`, `bituach-staging`, `bituach-prod`) | kind / minikube / k3d; separate clusters per environment | Docker Desktop k8s is already enabled on the machine; one cluster is enough to demonstrate namespace-level isolation, RBAC and quotas; separate clusters documented as the production recommendation |
| Q1 | Tooling runs in WSL2 `Ubuntu` | PowerShell / Git Bash | kubectl, helm, argocd, trivy, vault behave predictably on Linux; container builds and scripts are bash |
| Q1 | Registry `ghcr.io/danbarel78/bituach-yashir-{engine,data,ingest}`, **public** | Private GHCR; Docker Hub | Public packages need no `imagePullSecret` in manifests — keeps the secret story clean; private registry + `imagePullSecret` via ESO documented as the production variant |
| Q1 | Immutable tags `vX.Y.Z` and `vX.Y.Z-<sha>`; overlays pin **digests**; `latest` forbidden | Mutable `latest` / branch-name tags | Task explicitly asks for an immutable-tag policy |
| Q1 | Offline fallback `scripts/load-images.sh` (`docker save` → `ctr -n k8s.io images import`) | Rely solely on registry pulls | Docker Desktop may not resolve in-cluster registry names reliably |
| Q1 | GitHub Packages retention: keep last 3 tags per service | Unlimited retention | 500 MB free quota |
| Q2 | **Part 1 only**; Parts 2–3 supplied later | Infer and draft Parts 2–3 | Avoids unrequested work |
| Q3 | **T0 — implement exactly what the letter requires**; everything else designed and documented | T1 (live Prometheus/Grafana), T2 (alert firing demos), T3 (Argo Rollouts canary) | User instruction: "use exactly as stated in the letter. T0 only and all other will be designed and documented" |
| Q4 | **GitFlow** with realistic history (`feature/*` → `develop` → `release/*` → `main`, hotfix branch, annotated tags) | Trunk-based; single squashed commit | Task names GitFlow explicitly; git history is the reviewable evidence |
| Q4 | Public repository `danbarel78/bituach_yashir_pipeline` | Private repo | Deliverable link must be reviewable; matches public GHCR |
| Q4 | **No `gh` CLI**; instead `docs/git-workflow.md` with copy-paste tagging/commit/push commands | Install `gh` | User preference |
| Q4 | GitHub PAT (`write:packages`, `read:packages`) created at **Phase 4** | Create now | Only needed when Jenkins first pushes an image |
| Q4 | `base_version.json` (major/minor/patch) + branch-driven increment logic | Version literals in Jenkinsfile; `setuptools_scm` only | Explicit, auditable, single source of truth |
| Q5 | **Documentation language: English only** | Hebrew; bilingual | User instruction: "english only" |
| — | Python 3.12 + FastAPI for all services | Other languages/frameworks | User requirement |
| — | Python engineering baseline: `python-standards` Tier-1 policy (uv, `uv.lock`, src layout, ruff/mypy/pyright strict, pre-commit, coverage 80%) + `backend-Standards` FastAPI extension + `python-craft` advisory | bare pip/poetry; loose typing | User instruction: "use @backend-Standards to generate the services" |

### Confirmed technical exceptions (small, justified)

Two checks are kept **implemented** despite being outside the strict letter, because they *prove* features the letter does require (~15 min each). **User confirmed on 2026-11-18: keep both implemented.**

1. ArgoCD drift **self-heal** demonstration (proves GitOps actually reconciles).
2. NetworkPolicy **allow/deny** verification (proves the policies work, not just exist).

---

## 3. Implemented vs. documented-only (final)

### Implemented (working POC)

| Area | Concrete artifacts |
|---|---|
| Services | 3 FastAPI apps — `engine`, `data`, `ingest`; `GET /` → `{"service": "<name>"}`; multi-stage slim Dockerfile; non-root `securityContext` |
| Health | `/healthz` (liveness), `/readyz` (readiness), `startupProbe` — the task names Liveness/Readiness probes |
| Version evidence | `/version` → `{"service","version","gitSha","env"}` (proves the immutable tag reached the pod) |
| Internal comms | `engine` → `data` and `engine` → `ingest` over ClusterIP Services (`http://data:8000`, `http://ingest:8000`) |
| Jenkins | Containerized controller + full `Jenkinsfile` (stages in §10) |
| GitOps | ArgoCD app-of-apps; `base/` + `overlays/{dev,staging,prod}`; branch/tag-driven promotion; drift detection |
| Secrets | Vault (dev mode) → ESO → `ExternalSecret` → k8s Secret → `secretKeyRef` env var; `ClusterSecretStore` per namespace; GHCR push credential in Jenkins; gitleaks stage; rotation demo |
| Terraform | `modules/` + `envs/{dev,staging,prod}`: namespace, ResourceQuota, LimitRange, RBAC Role/RoleBinding, ServiceAccount, NetworkPolicy (default-deny + explicit allows), HPA, replica counts |
| Manifests | requests/limits, `strategy.rollingUpdate` (`maxSurge: 1`, `maxUnavailable: 0`), probes, securityContext, Service `ClusterIP`, Ingress + TLS (self-signed secret) |
| Version tooling | `base_version.json`, `ci/scripts/version.py`, `scripts/release.sh`, `CHANGELOG.md` |
| Docs | `README.md`, `docs/decisions.md` (1 pager), `docs/git-workflow.md`, `docs/versioning.md`, `docs/architecture.md`, `docs/secrets.md`, `docs/environment-topology.md`, `docs/observability-design.md`, `docs/runbook.md` |

### Documented only (designed, not deployed)

Prometheus / Grafana / Alertmanager stack and dashboards · alert rules and routing · SLO/SLA matrix per environment · Argo Rollouts canary and blue-green with migration path · PodDisruptionBudgets and anti-affinity · multi-cluster production topology · Vault production hardening (Raft, auto-unseal, k8s auth) · human RBAC matrix · private GHCR + `imagePullSecret` via ESO · Jenkins/CI observability · cost and quota management.

---

## 4. Architecture and topology

### Cluster topology

Single Docker Desktop cluster, three namespaces, one ArgoCD, one Vault, one ingress controller.

| | `bituach-dev` | `bituach-staging` | `bituach-prod` |
|---|---|---|---|
| Replicas per service | 1 | 2 | 2 (HPA max 3) |
| CPU request / limit | 50m / 250m | 100m / 500m | 200m / 1 (or 500m) |
| Memory request / limit | 64Mi / 128Mi | 128Mi / 256Mi | 256Mi / 512Mi |
| ResourceQuota | pods 12, cpu 2, mem 2Gi | pods 20, cpu 4, mem 4Gi | pods 24, cpu 6, mem 6Gi |
| HPA | disabled | min 2 / max 3, 70% CPU | min 2 / max 3, 70% CPU |
| NetworkPolicy | default-deny + allow | default-deny + allow | default-deny + allow (stricter egress) |
| Human RBAC | developers: edit | developers: view; CI: edit | read-only for devs; ArgoCD SA only |
| External access | Ingress `dev.bituach.localhost` | Ingress `staging.bituach.localhost` | Ingress `bituach.localhost` + TLS |
| Secrets source | Vault path `secret/dev/*` | `secret/staging/*` | `secret/prod/*` |

**Justification (documented):** namespaces in one cluster for the POC — cheapest, one control plane, easy to demonstrate RBAC/quota/NetworkPolicy isolation. Production recommendation: separate clusters for prod (blast radius, upgrade cadence, compliance boundary), staging+dev may share. Blast radius, noisy-neighbour and compliance arguments are written up in `docs/environment-topology.md`.

### Internal vs external channels

- **Internal:** `ClusterIP` Services; `engine` → `data`/`ingest` in-cluster DNS; no egress; NetworkPolicy allow-list only.
- **External:** ingress-nginx → Service → pods; TLS terminated at Ingress with a self-signed certificate stored as a TLS Secret (cert-manager/Let's Encrypt described as the production path).
- **SLA / monitoring / alerting differences:** documented per environment in `docs/observability-design.md` (dev: best-effort, no alerts; staging: SLO shadow, warning alerts; prod: 99.9% target, paging alerts, error-budget burn).

---

## 5. Service specification

| Service | Port | Endpoints | Responsibility |
|---|---|---|---|
| `engine` | 8000 | `/` → `{"service":"engine"}`, `/version`, `/healthz`, `/readyz`, `/aggregate` | Orchestrator; calls `data` and `ingest` over ClusterIP |
| `data` | 8000 | `/` → `{"service":"data"}`, `/version`, `/healthz`, `/readyz`, `/items` | Serves static/derived sample data |
| `ingest` | 8000 | `/` → `{"service":"ingest"}`, `/version`, `/healthz`, `/readyz`, `/ingest` | Accepts a payload and acknowledges it |

Shared conventions: Python 3.12, FastAPI, uvicorn, `uv` with `pyproject.toml` + committed `uv.lock` (no `requirements.txt`), `pytest` + `httpx` for tests, `ruff` + `mypy --strict` + `pyright` for quality gates, coverage floor 80%, non-root UID, read-only root filesystem where practical, structured JSON logging with no secret values, `APP_VERSION`/`GIT_SHA` build args baked in.

---

## 6. Versioning design

### `base_version.json` — single source of truth

```json
{
  "major": 1,
  "minor": 0,
  "patch": 0,
  "releasedAt": "2026-11-17T10:00:00Z",
  "releasedTag": "v1.0.0"
}
```

Holds the **last released** version. Only a human or `scripts/release.sh` edits it; CI only reads it.

### Branch-driven increment logic (`ci/scripts/version.py`)

| Branch / event | Computed version | `base_version.json` after | Registry tags | Deploys to |
|---|---|---|---|---|
| `feature/*` | `X.Y.Z-<branch>.N+<sha>` | unchanged | not pushed (build + test only) | nothing |
| push `develop` | `X.Y.(Z+1)-dev.N+<sha>` | unchanged | `X.Y.(Z+1)-dev.N-<sha>` | `dev` |
| `release/X.Y.0` | `X.Y.0-rc.N+<sha>` | unchanged | `X.Y.0-rc.N-<sha>` | `staging` |
| merge to `main` + tag `vX.Y.Z` | `X.Y.Z` (final) | set to `X.Y.Z` | `vX.Y.Z`, `vX.Y.Z-<sha>` (digest pinned) | `prod` (manual approval) |
| `hotfix/X.Y.(Z+1)` from tag | `X.Y.(Z+1)-hotfix.N+<sha>` → final `X.Y.(Z+1)` | set on merge | as above | staging → prod |

`N` = Jenkins `BUILD_NUMBER`; `<sha>` = 7-char commit SHA; local builds default to `0.0.0-local`.

### Guard rails (build fails, not warns)

- Strict SemVer validation; no version literals outside `base_version.json`.
- **Monotonicity:** computed version must sort above the newest existing `v*` tag (`git tag --sort=-v:refname`).
- `main` builds must come from a tag whose value equals `base_version.json` — no untagged production deploy.
- `latest` rejected in any overlay or kustomize image reference.
- `APP_VERSION` + `GIT_SHA` passed as Docker build args and verified by `/version`.

### Release, changelog, rollout

- `scripts/release.sh` (no `gh`): bump `base_version.json` → regenerate `CHANGELOG.md` from Conventional Commits → commit → annotated tag → print the exact `git push` commands.
- `CHANGELOG.md`: Keep-a-Changelog format, generated from Conventional Commits (`feat:`, `fix:`, `chore:`, `BREAKING CHANGE:`), grouped by version.
- Rollout strategy: **RollingUpdate** as the declared strategy (`maxSurge: 1`, `maxUnavailable: 0`, progress deadline); Blue-Green and Canary documented as the production evolution with an Argo Rollouts migration path.

---

## 7. Git workflow (no `gh` CLI)

Documented in `docs/git-workflow.md` with copy-paste commands:

1. `main` (protected, prod) and `develop` (integration) created in the first commit.
2. `feature/<name>` → PR into `develop` → CI builds and tests, no registry push.
3. `release/X.Y.0` cut from `develop` → CI pushes `rc` images → ArgoCD syncs `staging` → validation.
4. Merge `release/*` into `main` → annotated tag `vX.Y.Z` → CI pushes final images → ArgoCD syncs `prod` after manual approval.
5. Back-merge `main` → `develop`; delete the release branch.
6. `hotfix/X.Y.(Z+1)` from the release tag → PR to `main` → tag → back-merge to `develop`.
7. PRs created through the GitHub web UI (no `gh`); branch protection configured manually in repository settings.
8. Rollback = revert the GitOps overlay commit; ArgoCD re-syncs the previous digest.

Conventional Commits, tag naming (`vX.Y.Z`, annotated), and the branch→version→tag→environment cheat sheet are all in that document.

---

## 8. Secrets design

- **Runtime:** Vault (dev mode) holds `secret/{env}/{service}`; ESO `ClusterSecretStore` (Kubernetes auth) per namespace; `ExternalSecret` syncs to a k8s Secret named `<service>-secrets`; pods consume via `envFrom.secretRef` / `secretKeyRef` with `optional: false`.
- **No exposure:** no secret values in git, manifests, Helm values, Jenkinsfile, logs or image layers. gitleaks stage fails on any committed secret; app logging redacts configured keys.
- **CI/CD-time:** GHCR PAT stored in Jenkins credentials, injected via `withCredentials` into `docker login`, masked in logs, never echoed. Optional Vault-backed injection documented.
- **Rotation:** change the value in Vault → ESO refresh interval (60s) → pod restart (or reloader) → verify with `/config`-style endpoint that returns presence only, never the value.
- **Production variant (documented):** Vault Raft + auto-unseal, Kubernetes auth with bound service accounts, namespaced `SecretStore` instead of `ClusterSecretStore`, private GHCR with `imagePullSecret` generated by ESO.

---

## 9. Terraform design

- `terraform/modules/`: `namespace`, `rbac` (Role/RoleBinding + ServiceAccount), `networkpolicy` (default-deny + explicit allows), `resources` (ResourceQuota + LimitRange), `autoscaling` (HPA).
- `terraform/envs/{dev,staging,prod}`: module composition per environment with the values in §4; providers = `kubernetes` + `helm`; state local for the POC (remote state documented as production practice).
- Application Deployments stay in GitOps (kustomize); Terraform owns namespaces, quota, RBAC, SA, NetworkPolicy, HPA, and cluster-scoped platform objects — the split is documented as a deliberate boundary.

---

## 10. Jenkins pipeline

Containerized controller (`ci/docker/jenkins/Dockerfile` with docker CLI, kubectl, helm, trivy, python, git) + configuration-as-code.

| Stage | Detail | Gate |
|---|---|---|
| Checkout | full history + tags (`fetchTags`) | — |
| Version | `version.py` computes version; prints branch/version | monotonicity |
| Lint | `ruff check` | fail on error |
| Test | `pytest` with coverage | fail on any failure |
| SAST | `bandit -r services` | fail on HIGH |
| Dependency scan | `pip-audit` per service | fail on HIGH/CRITICAL |
| Build | `docker build --build-arg APP_VERSION --build-arg GIT_SHA` | — |
| Image scan | Trivy, report archived as artifact | fail on HIGH/CRITICAL |
| Push | `docker login` with Jenkins credential → GHCR, immutable tags + digest | branch-gated |
| GitOps update | `kustomize edit set image ...@<digest>` → commit to overlay | branch-gated |
| Deploy | ArgoCD auto-sync per overlay; `prod` requires manual approval | — |
| Verify | `scripts/smoke-test.sh` against the environment | fail on unhealthy |
| Retention | prune GHCR tags beyond the last 3 per service | — |

Branch behaviour: `feature/*` runs through image scan and stops; `develop` pushes and syncs `dev`; `release/*` pushes and syncs `staging`; `main`+tag pushes finals and syncs `prod`.

---

## 11. GitOps / ArgoCD design

- App-of-apps: one root app → three child apps (one per environment) → each child renders `gitops/overlays/<env>`.
- Sync policy: automated prune + self-heal for dev/staging; prod automated with manual sync (approval).
- Drift detection: UI/`argocd app diff`; self-heal demonstrated once.
- Image promotion: digest pinning in overlays; commit message records version, digest and pipeline URL.
- ArgoCD installed via Helm with values in `platform/argocd/values.yaml`; exposed at `https://argocd.localhost`.

---

## 12. Observability design (documented only)

- **Stack:** kube-prometheus-stack (Prometheus, Grafana, Alertmanager, kube-state-metrics, node-exporter) with etcd/scheduler/controller-manager/proxy scrape targets disabled — Docker Desktop's control plane is not scrapeable and default alerts would misfire.
- **metrics-server is NOT shipped with Docker Desktop** (verified 2026-11-18: the `v1beta1.metrics.k8s.io` APIService was absent). HPA has no backend without it, so `scripts/bootstrap.sh` installs `metrics-server` 3.14.0 into `kube-system` with `--kubelet-insecure-tls`, and `scripts/verify.sh` asserts the API is `Available`.
- **Per-service signals:** `/metrics` via `prometheus-fastapi-instrumentator`; ServiceMonitor per service; panels for RPS, p95 latency, 5xx ratio, restarts, HPA replicas.
- **Alerts:** error-rate SLO burn, p95 latency, restart loop, ExternalSecret not synced, ArgoCD `OutOfSync`/`Degraded`, certificate expiry, HPA at max.
- **Routing:** dev → none; staging → Slack/email warning; prod → paging (PagerDuty/on-call) with escalation.
- **Probes:** implemented (liveness/readiness/startup) and referenced as the health signal feeding both Kubernetes and the dashboards.
- **SLA matrix:** dev best-effort, staging 99.5% shadow, prod 99.9% with error budget and burn-rate alerts.

---

## 13. Repository layout

```
base_version.json   CHANGELOG.md   README.md   Makefile   .gitattributes   .gitignore
docs/               decisions.md  architecture.md  versioning.md  git-workflow.md
                    secrets.md  environment-topology.md  observability-design.md  runbook.md
services/           engine/  data/  ingest/  (each: app/main.py, tests/, requirements.txt, Dockerfile, pyproject.toml)
ci/                 Jenkinsfile  docker/jenkins/Dockerfile  scripts/{version.py,release.sh,scan.sh}
gitops/             argocd/  base/{engine,data,ingest}  overlays/{dev,staging,prod}
                    infra/{ingress,tls,argocd,vault,eso}
terraform/          modules/{namespace,rbac,networkpolicy,resources,autoscaling}  envs/{dev,staging,prod}
platform/           helm values: argocd, vault, external-secrets, ingress-nginx
scripts/            bootstrap.sh  verify.sh  load-images.sh  smoke-test.sh  teardown.sh
```

`.gitattributes` (`* text=auto eol=lf`, `*.ps1 text eol=crlf`) is committed first — `core.autocrlf=true` would otherwise corrupt every bash script.

---

## 14. Phase plan

| Phase | Content | Effort | Checkpoint |
|---|---|---|---|
| P0 | Scaffold, `.gitattributes`, `base_version.json`, `version.py`, `release.sh`, Makefile, `main`+`develop` | 0.75 h | version script outputs `0.1.0-dev.N` on develop |
| P1 | 3 FastAPI services, tests, Dockerfiles, local run | 1.5 h | `pytest` green; all three `/` endpoints answer |
| P2 | Cluster verify, ingress + TLS, ArgoCD, Vault, ESO, scripts | 2 h | ArgoCD UI reachable; Vault unsealed; ESO healthy |
| P3 | Terraform modules/envs, kustomize base/overlays, app-of-apps, first sync | 1.5 h | dev pods Running via ArgoCD |
| P4 | Jenkins container + Jenkinsfile + promotion logic + git-workflow doc | 1.5–2 h | pipeline pushes image and bumps overlay |
| P5 | Secrets end-to-end, rotation, gitleaks proof | 0.75 h | secret present in pod, absent from git/manifests/logs |
| P6 | Docs, GitFlow history polish, release tags | 1–1.5 h | `v1.0.0` tagged, README runnable |
| **Total** | | **≈ 9–10 h** | |

Every phase ends with a commit on the appropriate branch so the GitFlow history is genuine.

---

## 15. Acceptance checklist (task line → artifact)

| Requirement | Artifact |
|---|---|
| Local cluster POC, not mocked | Docker Desktop cluster, live URLs, README evidence |
| Jenkins build + tests + SAST/dep scan + image scan + GitOps deploy | `ci/Jenkinsfile`, archived Trivy report, ArgoCD sync history |
| Versioning: GitFlow, SemVer, tagging, changelog, rollout | `docs/versioning.md`, `base_version.json`, `version.py`, `CHANGELOG.md`, `strategy.rollingUpdate` |
| Vault + ESO, no secrets in manifests/code/logs, CI + runtime | `gitops/infra/{vault,eso}`, ExternalSecrets, gitleaks stage, rotation demo |
| Topology + justification + Terraform (quota/limits/RBAC/SA/netpol/HPA/replicas) | `terraform/**`, `docs/environment-topology.md` |
| Internal vs external channels, SLA/monitoring/alerting differences | `docs/architecture.md`, `docs/observability-design.md`, live Ingress |
| README + one-page decisions doc | `README.md`, `docs/decisions.md` |

---

## 16. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Windows CRLF breaks bash/entrypoints | `.gitattributes` in commit #1; verify line endings in CI |
| Tooling split Windows vs WSL | all tooling in WSL `Ubuntu`; bash scripts only |
| No `gh` → manual PRs | PRs via web UI; branch protection configured manually; documented steps |
| Public repo leaking secrets | gitleaks stage; no real secrets committed; Vault dev token stays in-cluster |
| Docker Desktop cannot pull GHCR in-cluster | `scripts/load-images.sh` fallback via `ctr images import` |
| GitHub Packages 500 MB quota | retention stage keeping last 3 tags per service |
| Single-node resource limits | HPA capped at 3; small requests; monitoring stack not deployed in T0 |
| Jenkins controller footprint | runs as container with modest JVM heap; documented as non-production |
| Vault dev mode loses data on restart | documented; ESO re-syncs; production hardening path written |

---

## 17. Open items

| # | Item | Owner | Status |
|---|---|---|---|
| 1 | **Documentation language** (Q5) | User | **RESOLVED 2026-11-18 — English only** |
| 2 | Downgrade the two 15-min proofs to documentation? | User | **RESOLVED 2026-11-18 — keep both implemented** |
| 3 | Create GitHub PAT (`write:packages`, `read:packages`) | User | due at Phase 4 |
| 4 | Repository `danbarel78/bituach_yashir_pipeline` public | User | confirmed public; observed empty (no branches) |
| 5 | Switch session from Plan mode to build agent | User | **RESOLVED 2026-11-18 — build mode active** |
| 6 | Parts 2 and 3 text | User | promised after Part 1 |
| 7 | `uv` dependency manager (Tier-1 policy requirement) | Agent | **RESOLVED** — installed in P1; `uv.lock` committed per service |
| 8 | `kubectl` + `helm` in WSL2 `Ubuntu` (Q1 requires Linux tooling) | Agent | **RESOLVED 2026-11-18** — kubectl 1.37.2 + helm 4.3.2 in `~/.local/bin`; kubeconfig copied from Windows |

---

## 18. Milestone log

| Date | Milestone | Status |
|---|---|---|
| 2026-11-17 | Scope confirmed (Q1–Q4); handoff.md moved to repo root; Q5 answered English-only; 15-min proofs kept | ✅ |
| 2026-11-17 | `data` → `ingest` rename completed in `services/ingest`; all quality gates green (ruff/mypy/pytest 88% coverage) | ✅ |
| 2026-11-17 | Corrupted bulk replace discovered in `.venv` (`metadata` → `metaingest`); venv rebuilt; source tree verified clean | ✅ |
| 2026-11-17 | `services/data/src/data/core/errors.py` left as-is per user instruction (known lint issue, not blocking ingest) | ⚠️ |

| Date | Milestone | Outcome | Next |
|---|---|---|---|
| 2026-11-17 | Scope confirmed | Part 1 only, T0 scope, GitFlow, public repo, no `gh`, `base_version.json` design approved | P0 scaffold |
| 2026-11-18 | Handoff relocated + open items closed | `handoff.md` moved to repo root; English-only docs; both 15-min proofs kept; Plan mode exited | P1 services |
| 2026-11-18 | **P0 scaffold complete** | Commit `433f9ac` on `main`: `.gitattributes` (LF enforcement), `.gitignore`, `base_version.json` (initial 0.0.0, relocated from stray `.opencode/skills/` location), `Makefile`, `ci/scripts/version.py`, `scripts/release.sh` (exec bit set); `develop` branched | P1 verify |
| 2026-11-18 | **P1 services verified** | `feature/p1-services` merged to `develop` (`e90ef9b`); fixed `fix/data-quality-gates` merge (`c16ef99`): duplicate `[tool.pyright]` keys in data `pyproject.toml`, undefined `exc` in data `errors.py`, missing `ConfigDict` import in data schemas, magic numbers in data tests; all gates green — ruff ✅ mypy ✅ pytest: engine 95.5%, data 88.5%, ingest 88.5%; all three `/` endpoints answered HTTP 200 over real uvicorn runs | P2 cluster/platform |
| 2026-11-18 | **P2 platform layer live** | `feature/p2-platform` merged to `develop`. Docker Desktop was **not running** at session start (restarted manually). Installed in WSL `Ubuntu`: kubectl 1.37.2 + helm 4.3.2 user-space (`~/.local/bin`, no sudo), kubeconfig wired. Platform: metrics-server 3.14.0, ingress-nginx 4.15.1 (LoadBalancer `172.18.0.5`, host 80/443), Argo CD 10.18.0 (v3.6.1), Vault 0.34.1 dev mode (2.0.4), ESO 2.15.0; self-signed TLS for 6 hosts generated at bootstrap (never committed). `scripts/verify.sh`: **21/21 checks pass** — Argo CD and Vault reachable over HTTPS, Vault initialized+unsealed, ESO 3 deployments ready, both ESO CRDs present | P3 Terraform + GitOps |
| 2026-11-18 | **P3 all three environments live via Argo CD** | `feature/p3-gitops` merged. Terraform: 5 modules + 3 envs, `terraform validate` clean, all applied. Kustomize `base/{engine,data,ingest}` + 3 overlays. App-of-apps root → 3 child apps. Repo pushed to GitHub (`main` `433f9ac`, `develop`). **dev + staging `Synced/Healthy`; prod synced only after a manual operation — the approval gate works.** Smoke: **27/27**. `/aggregate`: `all_reachable: true` proving engine→data and engine→ingest over ClusterIP. HPA reports real CPU (3%/70%), not `<unknown>`. **Drift self-heal proven**: scaled dev `data` to 4 replicas, Argo CD reverted to 1 within ~1.5 s. Images built with `APP_VERSION`/`GIT_SHA` and imported into the node via `ctr` | P3 review |
| 2026-11-18 | **G1 fixed + per-service hostnames** | Review found two §5 deviations: `data` had no `/items` and `ingest` had no `/ingest`. Both implemented with tests (data 89.9%, ingest 89.7% coverage, ruff+mypy clean). Added `ingress-services.yaml` per overlay so each service answers on its own host (`engine.dev.bituach.localhost`, `data.*`, `ingest.*`; same for staging/prod) in addition to the path prefixes. TLS SAN list extended to 15 names and all 5 namespaces re-issued. Verified live: `/items` → 4-item catalog, `POST /ingest` → `accepted: true` and never echoes payload values. Smoke: **27/27** across dev/staging/prod. Root cause of the user-reported 404s: requests were made to the ingress host root, which has no rule — documented below | P4 Jenkins |
| 2026-11-18 | **Pre-P4 review checkpoint** | Re-verified current state after an unexpected session termination: working tree clean, all four Argo CD apps `Synced/Healthy`, `scripts/verify.sh` **21/21**, prod smoke **9/9**, engine tests green, Argo CD UI HTTP 200, drift self-heal re-measured at **~2.5 s** (dev `data` scaled to 4, reverted to 1). Wrote `docs/review-and-walkthrough.md`: plain-language concept summary, requirement-coverage matrix, manager script, 15 anticipated Q&A, and hands-on guide (local run, Argo CD UI, drift and approval-gate demos, logs, rebuild/import, teardown). Documented the honest status: P4 Jenkins, P5 secret wiring and P6 deliverables (README, `docs/decisions.md`, other docs, `CHANGELOG.md`, `v1.0.0` tag) are still outstanding; overlays still pin `:local` rather than digests | P4 Jenkins |
| 2026-11-18 | **First images published to GHCR (public)** | Pushed `0.0.1-dev.0-11e3604` for all three services with a PAT (classic, `write:packages`). Packages defaulted to **private**; set to public in the UI and linked check pending. Verified logged-out pulls with matching digests: engine `sha256:8cad16f7…78c05`, data `sha256:26e14ab0…56d50`, ingest `sha256:0f8239d4…cc82c`. Overlays intentionally still `newTag: local` — digest pinning is the next P4 step. Token only used via `--password-stdin`, never written to the repo; **must be rotated** (over-privileged classic PAT exposed in chat) | P4 Jenkins + digest pins |
| 2026-11-18 | **Digest pinning cutover complete (all envs from GHCR)** | `feature/digest-pinning` merged to `develop` (`34c07ec`, pushed). All three overlays now reference `ghcr.io/...@sha256:…` instead of `newTag: local`; rendered output verified with `kubectl kustomize` for dev/staging/prod. dev + staging auto-synced and rolled out; **prod stayed `OutOfSync` until a manual sync** — the approval gate is proven again. Prod synced via the Application `operation` field, then 6 pods rolled out. In-cluster pull proven: a one-off pod with `imagePullPolicy: Always` pulled the engine digest anonymously in 49 ms (56.7 MB). `/version` in prod: `0.0.1-dev.0+11e3604`, `environment: prod`; `/aggregate` `all_reachable: true`; smoke **27/27** (9 per env) | P4 Jenkins |

### Ingress host map (verified 2026-11-18)

| Environment | Per-service hosts | Path-prefix host |
|---|---|---|
| dev | `engine.dev.bituach.localhost`, `data.dev.…`, `ingest.dev.…` | `dev.bituach.localhost/{engine,data,ingest}/` |
| staging | `engine.staging.bituach.localhost`, `data.staging.…`, `ingest.staging.…` | `staging.bituach.localhost/…` |
| prod | `engine.bituach.localhost`, `data.bituach.localhost`, `ingest.bituach.localhost` | `bituach.localhost/…` |

Note: Windows does not resolve `*.localhost`; browsers do. Use
`curl -k --resolve <host>:443:127.0.0.1 https://<host>/` from a shell.

---

## 19. Environment as observed

| Item | Value |
|---|---|
| OS / shell | Windows 10/11, PowerShell; WSL2 available (`Ubuntu` distro, `docker-desktop` default) |
| Working dir | `C:\Users\dbarel\OneDrive\Documents\MyProjects\bituach_yashir_demo\bituach_yashir_pipeline` |
| Docker | Docker Desktop installed at `%LOCALAPPDATA%\Programs\DockerDesktop`; **not running at session start** on 2026-11-18 (started manually); engine 29.8.2; k8s v1.36.1, node `desktop-control-plane` |
| Present | `docker`, `kubectl` (1.37.2), `helm` (4.3.x), `terraform`, `git`, `python` 3.12.7 (+ py 3.11), `java` 21 |
| WSL2 `Ubuntu` | kubectl 1.37.2 + helm 4.3.2 installed user-space in `~/.local/bin` (no sudo needed — `sudo` requires an interactive password); kubeconfig copied from Windows, API server reachable on `127.0.0.1` (mirrored networking) |
| WSL2 / Docker | **Docker Desktop WSL integration is NOT enabled** for `Ubuntu`. `docker` resolves through Windows interop but cannot reach the daemon, so image builds/imports are run from PowerShell on this machine. `scripts/load-images.sh` detects this and fails with an actionable message. Enabling integration is a one-click change in Docker Desktop settings. |
| Missing | `kind`, `minikube`, `k3d`, `jenkins`, `argocd` CLI, `vault` CLI, `trivy`, `gh` |
| Git identity | `Daniel Barel <dbarel@gmail.com>` |
| Git config | `core.autocrlf=true`, `init.defaultBranch=master` |
| Remote | `origin` exists, **empty** (no branches); local `main` has 1 commit, `develop` 3 (as of 2026-11-18); first push still pending |
| Python note | `python` resolves to msys64 3.12.7; `py -3.11` also available |
| Skills present | `python-standards` (Tier-1), `python-craft` (advisory), `python-review` (combined), `backend-Standards` (FastAPI extension), `architecture-ux-generate-flow` |

---

## 20. Next action

**P4 — Jenkins CI/CD** (per §14): containerized controller (`ci/docker/jenkins/Dockerfile`), configuration-as-code, full `Jenkinsfile` with the §10 stages (version → lint → test → SAST → dependency scan → build → Trivy → push → GitOps overlay update → verify → retention), plus `ci/scripts/scan.sh` and `docs/git-workflow.md`.

**Open item #3 blocks the push stages:** no GitHub PAT yet and Docker is not authenticated to `ghcr.io`. The user chose to defer the push; images currently reach the cluster via `ctr images import` (`scripts/load-images.sh`, executed from PowerShell because Docker Desktop WSL integration is off). P4 needs either the PAT (recommended path) or the Jenkinsfile's push stage demonstrated via the local-import fallback.

Known follow-ups recorded during P3:
- Overlays pin `newTag: local`; they must switch to `newImage@sha256:…` digests once GHCR push works (§6 requires immutable digest pins).
- All three child Applications track `targetRevision: develop`; promotion wiring (release branch for staging, tag for prod) is P4/P6 work.
- Argo CD emits a finalizer warning (`resources-finalizer.argocd.argoproj.io` lacks a `/`); cosmetic on k8s 1.36, left as the Argo CD documented value.
