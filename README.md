# Bituach Yashir - DevOps delivery pipeline

A working proof of concept for the Bituach Yashir platform: three FastAPI
services delivered through Jenkins, GHCR and Argo CD to three isolated
Kubernetes environments, with Terraform-managed guard rails and immutable
image digests.

The POC runs on Docker Desktop Kubernetes. It is intentionally a local,
single-node demonstration, not a production deployment.

**Current release:** `v1.0.4` (see [`CHANGELOG.md`](CHANGELOG.md)).

## What this demonstrates

| Area | Implementation |
|---|---|
| Local Kubernetes POC | Docker Desktop cluster, three namespaces: `bituach-dev`, `bituach-staging`, `bituach-prod` |
| Services | `engine`, `data`, `ingest`; FastAPI, Python 3.12, health probes, `/version` evidence |
| CI/CD | Jenkins multibranch pipeline: tests, lint, types, SAST, dependency audit, image scan, push, GitOps write-back |
| GitOps | Argo CD app-of-apps; dev and staging auto-sync, production requires a manual Sync |
| Versioning | GitFlow, Semantic Versioning, `base_version.json`, annotated `vX.Y.Z` tags, generated changelog |
| Image policy | Immutable tags and digest-pinned overlays; `latest` and `local` are rejected by CI |
| Terraform | Namespaces, ResourceQuota, LimitRange, RBAC, ServiceAccounts, NetworkPolicies, HPA |
| Internal/external access | ClusterIP Services internally; ingress-nginx with TLS externally |
| Secrets | Vault and External Secrets Operator installed; CI-time credentials implemented; runtime pod wiring is the remaining gap |
| Rollout | RollingUpdate (`maxSurge: 1`, `maxUnavailable: 0`); canary and blue-green are documented evolutions |

## Status at a glance

| Capability | Status |
|---|---|
| Three services build, test and run | Implemented |
| Jenkins pipeline through image push and GitOps | Implemented and exercised |
| Argo CD dev/staging auto-sync | Implemented |
| Argo CD prod manual approval | Implemented |
| Terraform environment guard rails | Implemented |
| GitFlow releases through `v1.0.4` | Implemented |
| Vault + ESO runtime secret path | Partial: Vault/ESO installed, `ExternalSecret`/`secretKeyRef` not yet wired |
| Prometheus / Grafana / Alertmanager | Design only |
| Argo Rollouts canary / blue-green | Design only |
| gitleaks, tag retention, `progressDeadlineSeconds` | Not implemented |

> Some design documents deliberately describe the target state. When a document
> and the code disagree, the code and the "Implemented vs designed" table below
> are authoritative.

## Architecture

### Delivery path

```text
developer change
      |
      v
GitHub branch / pull request
      |
      v
Jenkins multibranch pipeline
  lint -> types -> tests -> SAST -> dependency audit
      -> image build -> Trivy scan -> GHCR push
      -> digest write-back to gitops/overlays/<env>
      |
      v
Argo CD reconciles the overlay
      |
      +--> dev      automated sync
      +--> staging  automated sync
      +--> prod     manual Sync (approval gate)
```

### Runtime path

```text
browser / curl
      |
      v
ingress-nginx (TLS)
      |
      +--> engine  ---ClusterIP---> data
      |                   \------> ingest
      +--> data
      +--> ingest
```

`engine` is the only service that calls the other two. The internal calls use
Kubernetes DNS and ClusterIP Services, not `localhost`.

## Services

| Service | Cluster port | Local port | Main endpoints |
|---|---:|---:|---|
| `engine` | 8000 | 8000 | `/`, `/version`, `/healthz`, `/readyz`, `/aggregate` |
| `data` | 8000 | 8001 | `/`, `/version`, `/healthz`, `/readyz`, `/items` |
| `ingest` | 8000 | 8002 | `/`, `/version`, `/healthz`, `/readyz`, `POST /ingest` |

`/version` is the deployment evidence: it returns the version, git SHA and
environment baked into the running image.

`POST /ingest` rejects a negative `claim_amount` with HTTP `422`. A positive
amount returns HTTP `200`.

## Environments

| | dev | staging | prod |
|---|---|---|---|
| Namespace | `bituach-dev` | `bituach-staging` | `bituach-prod` |
| Replicas per service | 1 | 2 | 2 |
| HPA | disabled | 2-3 at 70% CPU | 2-3 at 70% CPU |
| Argo CD sync | automated, prune, self-heal | automated, prune, self-heal | **manual Sync** |
| Argo CD tracks | `develop` | `develop` | `main` |
| External host | `dev.bituach.localhost` | `staging.bituach.localhost` | `bituach.localhost` |
| Per-service hosts | `engine.dev...`, `data.dev...`, `ingest.dev...` | same, `.staging...` | `engine.bituach...`, `data.bituach...`, `ingest.bituach...` |
| TLS | self-signed | self-signed | self-signed |
| Secrets source (target) | Vault path `secret/dev/*` | `secret/staging/*` | `secret/prod/*` |

Dev and staging share the `develop` branch but use different overlay
directories. A `develop` build updates only `gitops/overlays/dev`; a
`release/*` or `hotfix/*` build updates `gitops/overlays/staging`.

Production is updated only by a tagged `main` build, followed by a human Sync in
Argo CD.

## Quick start

### Prerequisites

- Docker Desktop with Kubernetes enabled.
- A bash environment for the scripts. WSL2 Ubuntu is the validated environment.
- `git`, `kubectl`, `helm`, `terraform`, `uv`, `curl`, `openssl`.
- Python 3.12 (installed on demand by `uv`).
- Optional: a GitHub PAT with `repo` and `write:packages` for Jenkins to push
  images and update the GitOps repository.

The repository is public:

```bash
git clone https://github.com/danbarel78/bituach_yashir_pipeline.git
cd bituach_yashir_pipeline
```

### 1. Install the platform layer

```bash
./scripts/bootstrap.sh
./scripts/verify.sh
```

`bootstrap.sh` installs metrics-server, ingress-nginx, Argo CD, Vault and the
External Secrets Operator. It is idempotent and can be used to repair the
platform.

Expected verification result:

```text
All 21 checks passed.
```

Useful endpoints:

| URL | Purpose |
|---|---|
| `https://argocd.localhost` | Argo CD UI |
| `https://vault.localhost` | Vault UI |
| `https://dev.bituach.localhost` | dev path-prefix entry point |
| `https://staging.bituach.localhost` | staging path-prefix entry point |
| `https://bituach.localhost` | production path-prefix entry point |

Argo CD admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

Vault runs in dev mode with the static root token `root`. That is a local POC
convenience and must not be copied to a real environment.

### 2. Create the application environments with Terraform

Terraform owns the namespaces and platform guard rails. Run each environment
from its directory:

```bash
for env in dev staging prod; do
  (
    cd "terraform/envs/$env"
    terraform init -input=false
    terraform apply -auto-approve
  )
done
```

Terraform state is local for this POC. Remote state and a separate production
cluster are the documented production evolution.

### 3. Register the GitOps applications

```bash
kubectl apply -f gitops/argocd/root-app.yaml
kubectl -n argocd get applications
```

Expected: the root application plus `bituach-dev`, `bituach-staging` and
`bituach-prod`.

Dev and staging reconcile automatically. Production shows `OutOfSync` after a
release until a human clicks **Sync**.

### 4. Start Jenkins

On Windows:

```powershell
make jenkins-build
make jenkins-up
```

or:

```powershell
pwsh ./ci/jenkins.ps1 build
pwsh ./ci/jenkins.ps1 up
```

Jenkins is available at `http://localhost:8080`. The default local admin
password is `admin`; override it with `JENKINS_ADMIN_PASSWORD`.

Create a Jenkins username/password credential named `github-token` with a
GitHub PAT that can push to GHCR and to the repository. The pipeline references
this credential ID for both `docker login` and the GitOps commit.

The multibranch job is created from `ci/docker/jenkins/init.groovy.d/`. Jenkins
scans the repository every five minutes; use **Scan Multibranch Pipeline Now**
when you do not want to wait.

### 5. Verify the deployed services

```bash
./scripts/smoke-test.sh --env dev
./scripts/smoke-test.sh --env staging
./scripts/smoke-test.sh --env prod
```

Expected per environment:

```text
All 9 smoke checks passed.
```

Direct checks:

```bash
curl -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 \
  https://engine.dev.bituach.localhost/version

curl -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 \
  https://engine.dev.bituach.localhost/aggregate
```

`/aggregate` proves that `engine` reaches `data` and `ingest` over ClusterIP.

Negative-claim check:

```bash
curl -sk --resolve ingest.dev.bituach.localhost:443:127.0.0.1 \
  -X POST https://ingest.dev.bituach.localhost/ingest \
  -H "Content-Type: application/json" \
  -d '{"source":"demo","payload":{"claim_amount":-100}}'
```

Expected: `HTTP 422`. Change `-100` to `100` for the positive control
(`HTTP 200`).

On Windows, use `curl.exe`; `*.localhost` resolves in browsers but not always in
the Windows resolver, hence the explicit `--resolve`.

## Local development and tests

Run the quality gates from the repository root:

```bash
make install
make lint
make format
make typecheck
make test
make security
make version
```

`make install` installs dependencies. `make test` runs pytest with the 80%
coverage floor. `make security` runs bandit locally; Jenkins also runs pip-audit
and the Trivy image scan as authoritative gates.

Run the services locally on distinct ports:

```bash
# terminal 1 - data
cd services/data
uv sync --frozen --extra dev
uv run uvicorn data.main:app --reload --port 8001
```

```bash
# terminal 2 - ingest
cd services/ingest
uv sync --frozen --extra dev
uv run uvicorn ingest.main:app --reload --port 8002
```

```bash
# terminal 3 - engine
cd services/engine
uv sync --frozen --extra dev
DATA_SERVICE_URL=http://localhost:8001 \
INGEST_SERVICE_URL=http://localhost:8002 \
uv run uvicorn engine.main:app --reload --port 8000
```

In PowerShell, set the environment variables separately:

```powershell
$env:DATA_SERVICE_URL = "http://localhost:8001"
$env:INGEST_SERVICE_URL = "http://localhost:8002"
uv run uvicorn engine.main:app --reload --port 8000
```

Then:

```bash
curl http://localhost:8000/aggregate
```

Docker images can be built locally with:

```bash
make docker-build
```

The committed overlays reference immutable GHCR digests, not local tags.
`scripts/load-images.sh` is an offline fallback for importing locally built
images into the Docker Desktop node; it is not the normal delivery path.

## CI/CD pipeline

The pipeline is defined in [`ci/Jenkinsfile`](ci/Jenkinsfile).

| Stage | What it does |
|---|---|
| Preflight | Refuses mutable image tags; honours `[skip ci]` only on `develop` and `main` |
| Version | Computes the SemVer version from `base_version.json` and the branch |
| Setup | `uv sync --frozen --extra dev` for all services |
| Lint | `ruff check` and `ruff format --check` |
| Types | `mypy` per service |
| Test | `pytest --cov` per service plus the version-policy tests |
| SAST | bandit |
| Dependencies | pip-audit |
| Build | Docker build with `APP_VERSION` and `GIT_SHA` |
| Image scan | Trivy, fail on fixable HIGH/CRITICAL findings |
| Push | GHCR, immutable image tag and digest |
| GitOps | Writes the digest pin to the target overlay and commits with `[skip ci]` |
| Wait for Argo CD | Waits for the exact pushed revision and `Synced/Healthy` on dev/staging |
| Smoke | Runs `scripts/smoke-test.sh` after the sync |
| Prod handoff | Prints the manual approval URL for production |

Branch behaviour:

| Branch | Computed version | Image pushed | Deployed to |
|---|---|---|---|
| `feature/*`, `fix/*`, `bugfix/*`, `chore/*`, `docs/*`, `refactor/*`, `test/*`, `dependabot/*` | `X.Y.(Z+1)-<slug>.N+<sha>` | No | Nothing |
| `develop` | `X.Y.(Z+1)-dev.N+<sha>` | Yes | dev |
| `release/X.Y.Z` | `X.Y.Z-rc.N+<sha>` | Yes | staging |
| `hotfix/X.Y.Z` | `X.Y.Z-hotfix.N+<sha>` | Yes | staging |
| `main` at tag `vX.Y.Z` | `X.Y.Z` | Yes | prod overlay, then manual Sync |

`N` is the Jenkins build number and `<sha>` is the seven-character commit SHA.
The Git tag keeps the `v`; the container tag does not.

## Versioning and release

The full operator runbook is in
[`docs/git-workflow.md`](docs/git-workflow.md). The policy and trade-offs are in
[`docs/versioning.md`](docs/versioning.md).

The normal release path:

```text
fix or feature branch -> develop (dev)
                      -> release/X.Y.Z (staging)
                      -> main + tag vX.Y.Z (prod, manual Sync)
                      -> back-merge main into develop
```

Release commands, from a clean, up-to-date `main`:

```bash
git switch main
git pull --ff-only origin main
./scripts/release.sh patch        # or minor / major
git push origin main --follow-tags
```

On Windows, the PowerShell port behaves the same way:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release.ps1 patch
```

`release.sh` and `release.ps1`:

- bump `base_version.json`;
- regenerate `CHANGELOG.md` from Conventional Commits;
- commit the bump;
- create the annotated `vX.Y.Z` tag;
- print the push commands.

They do not push. After the release, back-merge `main` into `develop` so the
next develop build can compute a version above the new tag:

```bash
git switch develop
git pull --ff-only origin develop
git merge --no-ff main -m "Merge branch 'main' into develop"
git push origin develop
```

The release build is the `main` branch build at the tagged commit. Jenkins does
not discover tags independently; `main` and the tag are pushed together.

A documentation-only commit pushed directly to `main` should include `[skip ci]`.
An untagged `main` build is rejected by the version guard unless it is a real
release commit.

Pull requests are opened in the GitHub web UI; the workflow does not depend on
the `gh` CLI.

## Secrets

CI-time secrets are implemented:

- Jenkins stores the GHCR/repository PAT as the credential `github-token`.
- The token is injected with `withCredentials` and `--password-stdin`.
- It is never written to the repository or echoed to the build log.

Runtime secrets are specified but not fully wired:

- Vault and ESO are installed and healthy.
- `ClusterSecretStore`, `ExternalSecret` and `secretKeyRef` are not yet applied.
- `docs/secrets.md` is the target design and acceptance sequence.

The Vault dev root token `root` exists in `platform/values/vault.yaml` for the
local in-memory POC. It is an explicit local exception. Production uses Vault
Raft, Kubernetes auth and short-lived tokens.

## Terraform

Terraform creates the platform contract for each environment:

```text
terraform/modules/
  namespace/      Namespace and Pod Security labels
  resources/      ResourceQuota and LimitRange
  rbac/           ServiceAccount, Role and RoleBinding
  networkpolicy/  default-deny plus explicit allows
  autoscaling/    HorizontalPodAutoscaler v2

terraform/envs/
  dev/  staging/  prod/
```

Application Deployments, Services and Ingresses stay in `gitops/` and are
managed by Argo CD. Terraform and Argo CD do not own the same objects.

See [`docs/environment-topology.md`](docs/environment-topology.md) for the
namespace-versus-cluster decision, the environment matrix and the sizing
trade-offs.

## Internal and external channels

- Internal service-to-service traffic uses ClusterIP Services
  (`http://data:8000`, `http://ingest:8000`).
- External customer traffic uses ingress-nginx with TLS termination.
- `/healthz` is the liveness signal; `/readyz` is the readiness signal.
- `/version` and `/aggregate` provide runtime evidence for a reviewer.

Prometheus, Grafana, Alertmanager, SLO dashboards and paging alerting are
designed but not deployed in the T0 scope. Health and readiness probes are
implemented; service metrics instrumentation is part of the observability
design and is not yet added.

## Key decisions and trade-offs

| Decision | Alternative rejected | Why |
|---|---|---|
| One Docker Desktop cluster, three namespaces | Separate cluster per environment | Cheapest and fastest POC; shows quota, RBAC and NetworkPolicy isolation in one control plane. Production recommendation is a separate prod cluster. |
| GitFlow: `feature/fix -> develop -> release -> main + tag` | Trunk-based development | The assignment names GitFlow; the tag gives a reviewable answer to "what is in production?" |
| SemVer and immutable image digests | Mutable `latest` tags | Two pods can never run different code under the same name; `/version` proves the deployed identity. |
| RollingUpdate (`maxSurge: 1`, `maxUnavailable: 0`) | Blue-green or canary now | Lowest operational complexity for a local POC; safer strategies are documented as the production evolution. |
| Terraform owns namespaces, quota, RBAC, NetworkPolicy and HPA | Put everything in GitOps | Guard rails must exist before workloads and app teams must not raise their own limits. |
| Jenkins controller container with host Docker socket | Dedicated build agents / Kaniko | Reproducible one-container POC; the socket mount is documented as a non-production shortcut. |
| Public GHCR packages | Private registry with `imagePullSecret` | Keeps the secret story small; private registry and ESO-generated pull secrets are the documented production variant. |
| Vault dev mode for the POC | Production Vault with Raft and auto-unseal | Local in-memory Vault is sufficient for the demonstration; hardening is documented separately. |

## Implemented vs designed

| Area | State |
|---|---|
| Services and probes | Implemented |
| Jenkins build, test, scan, push and GitOps write-back | Implemented |
| Argo CD app-of-apps and three environments | Implemented |
| Production manual approval | Implemented |
| Terraform guard rails | Implemented |
| GitFlow, SemVer, tags and changelog | Implemented through `v1.0.4` |
| Vault and ESO installation | Implemented |
| Vault -> ESO -> Pod runtime secret path | Specified in `docs/secrets.md`, not applied |
| Prometheus / Grafana / Alertmanager | Design only |
| SLO/alerting and paging | Design only |
| Argo Rollouts canary/blue-green | Design only |
| gitleaks, tag retention, `progressDeadlineSeconds` | Not implemented |
| Multi-cluster production topology | Design only |
| Private GHCR and `imagePullSecret` via ESO | Design only |

POC-only shortcuts:

- Vault runs in dev mode with a static root token.
- TLS uses a locally generated self-signed certificate.
- GHCR packages are public.
- Jenkins mounts the host Docker socket.
- Terraform state is local.
- Argo CD uses the local admin account.

These are acceptable for the assignment but are not production security or
availability claims.

## Repository layout

```text
README.md                  this file
CHANGELOG.md               release history
base_version.json          last released version (single source of truth)
Makefile                   local developer entry point
architecture-deck.html     visual walkthrough (open in a browser)

ci/                        Jenkinsfile, controller image, version/scan/GitOps scripts
docs/                      versioning, secrets, topology, workflow and review docs
gitops/                    Argo CD applications, Kustomize base and overlays
platform/                  Helm values for ingress, Argo CD, Vault, ESO, metrics-server
scripts/                   bootstrap, verify, smoke, teardown, image load, release
services/                  engine, data and ingest FastAPI services
terraform/                 reusable modules and dev/staging/prod compositions
```

## Documentation

> Several documents preserve the state of a specific milestone. The status table
> above reflects the current repository; use the documents for design rationale,
> policy and commands, not as live status reports.

| Document | Purpose |
|---|---|
| [`docs/git-workflow.md`](docs/git-workflow.md) | Developer-to-production runbook with expected outputs |
| [`docs/versioning.md`](docs/versioning.md) | GitFlow, SemVer, image tagging, changelog and rollout policy |
| [`docs/secrets.md`](docs/secrets.md) | Vault/ESO design, CI-time versus runtime secrets, rotation and acceptance |
| [`docs/environment-topology.md`](docs/environment-topology.md) | Namespace-versus-cluster decision, environment matrix and Terraform walkthrough |
| [`docs/requirements-coverage.md`](docs/requirements-coverage.md) | Requirement-by-requirement audit and known gaps |
| [`docs/review-and-walkthrough.md`](docs/review-and-walkthrough.md) | Plain-language walkthrough, demos and likely review questions |
| [`docs/standards/backend-standards.md`](docs/standards/backend-standards.md) | Python/FastAPI engineering baseline |
| [`handoff.md`](handoff.md) | Engineering project record and milestone log |
| [`platform/README.md`](platform/README.md) | Installed platform components, versions and endpoints |
| [`terraform/modules/README.md`](terraform/modules/README.md) | Terraform module responsibilities and the GitOps boundary |
| `services/*/README.md` | Per-service endpoints, configuration and local commands |
| [`architecture-deck.html`](architecture-deck.html) | Self-contained visual walkthrough with keyboard navigation |

## Troubleshooting

**`*.localhost` does not resolve in curl**

Use `--resolve`:

```bash
curl -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 \
  https://engine.dev.bituach.localhost/version
```

**TLS certificate warning**

The POC uses a self-signed certificate. `curl -k` is expected. Browsers require
a one-time exception.

**Docker Desktop cluster is not running**

Start Docker Desktop and confirm Kubernetes is enabled:

```bash
kubectl get nodes
```

The POC was validated on a single `desktop-control-plane` node.

**WSL cannot reach the Docker daemon**

If Docker Desktop WSL integration is disabled, run Docker commands from
PowerShell. `scripts/load-images.sh` detects this and prints an actionable error.

**Jenkins build is `NOT_BUILT`**

The commit contains `[skip ci]` and the branch is `develop` or `main`. This is
the guard that prevents the GitOps digest commit from triggering itself. It is
expected.

**`main` build fails because the commit is not tagged**

`main` builds are release builds and must come from a tag whose value equals
`base_version.json`. For a documentation-only change, put `[skip ci]` in the
commit message. For a code change, cut a release with `scripts/release.sh` or
`scripts/release.ps1`.

**Production is `OutOfSync`**

That is the approval gate. Open Argo CD, inspect `bituach-prod`, and click
**Sync** when you are ready to deploy the pinned digests.

**`kubectl get externalsecret -A` returns nothing**

The runtime secret path is not implemented yet. Vault and ESO are installed;
`docs/secrets.md` is the specification for the remaining wiring.

**Develop build fails with a monotonicity error after a release**

`develop` is behind `main` and still has the old `base_version.json`. Merge
`main` back into `develop` and rerun the build.

**Argo CD reports a finalizer warning**

`resources-finalizer.argocd.argoproj.io` lacks a `/`. It is cosmetic on the
current Kubernetes version and is the documented Argo CD value.

## Cleanup

Remove the platform and application namespaces:

```bash
./scripts/teardown.sh --yes
```

Keep the application namespaces:

```bash
./scripts/teardown.sh --yes --keep-data
```

`metrics-server` is left installed in `kube-system`; remove it separately if
desired:

```bash
helm -n kube-system uninstall metrics-server
```

## Scope note

This repository is the Part 1 DevOps POC. The platform, delivery loop,
versioning and topology are implemented. Runtime secret injection is the main
remaining implementation gap; the observability stack and advanced rollout
strategies are documented designs rather than deployed components.
