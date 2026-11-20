# Version management strategy

This document answers the version-management part of the assignment: the
branching strategy, Semantic Versioning conventions, container image tagging
policy, changelog management and the Kubernetes rollout strategy.

It describes **what is enforced by code** and **what is policy only**, and it
points at the artifact that proves each claim. The companion documents are
`docs/git-workflow.md` (operator commands) and `handoff.md` §6 (the original
decision record).

## 1. Decisions at a glance

| Concern | Decision | Enforced by |
|---|---|---|
| Branching | GitFlow: `feature/*` or `fix/*` → `develop` → `release/*` → `main`, plus `hotfix/*` | `docs/git-workflow.md`, branch protection, `ci/scripts/version.py` (rejects unknown branches) |
| Version scheme | Semantic Versioning 2.0.0, single numeric source of truth in `base_version.json` | `ci/scripts/version.py`, `ci/tests/test_version.py` |
| Pre-release builds | `-dev.N`, `-rc.N`, `-hotfix.N`, `-<branch-slug>.N` with `+<sha>` build metadata | `ci/scripts/version.py` |
| Image tags | Immutable only. `latest` and `local` are refused. Overlays pin **digests** | Jenkins `Preflight` guard, `gitops/overlays/*/kustomization.yaml` |
| Changelog | Keep a Changelog, generated from Conventional Commits | `scripts/release.sh`, `CHANGELOG.md` |
| Rollout | `RollingUpdate` with `maxSurge: 1`, `maxUnavailable: 0` | `gitops/base/*/deployment.yaml` |
| Rollout (production evolution) | Canary via Argo Rollouts, then blue-green for major versions | Documented, not deployed (T0 scope) |

## 2. Branching strategy — GitFlow

### 2.1 Branches

| Branch | Purpose | Merges into | Deploys to | Lifetime |
|---|---|---|---|---|
| `main` | Released code. Every release commit is reachable from an annotated `vX.Y.Z` tag; the CI digest-pin commit that follows a release is untagged but marked `[skip ci]` | — | prod (after manual Argo CD sync) | permanent |
| `develop` | Integration of finished features | — | dev (automatic) | permanent |
| `feature/<name>` | One change | `develop` via PR | nothing (build + test only) | deleted after merge |
| `fix/<name>` | A bug fix (alias of `bugfix/*`; both are accepted) | `develop` via PR | nothing | deleted after merge |
| `bugfix/<name>`, `chore/<name>`, `docs/<name>`, `refactor/<name>`, `test/<name>` | Same rule as `feature/*`, different intent | `develop` | nothing | deleted after merge |
| `release/X.Y.Z` | Stabilisation; only fixes, no new scope | `main`, then back-merge to `develop` | staging (automatic) | deleted after release |
| `hotfix/X.Y.Z` | Urgent fix cut from a release tag | `main`, then back-merge to `develop` | staging → prod | deleted after merge |
| `dependabot/*` | Automated dependency updates | `develop` | nothing | managed by the bot |

“Deploys to staging” means the release/hotfix build writes the staging overlay
to `develop`; the staging Application tracks `develop`, so no branch retarget is
needed. The production approval is the manual Argo CD Sync, not a second review.

`main` and `develop` are protected: changes arrive only through a pull request,
CI must be green, and only the release manager merges into `main`. No
environment is deployed from a developer workstation.

### 2.2 Flow

```
feature/x ──PR──► develop ──cut──► release/1.2.0 ──PR──► main ──tag v1.2.0──► prod
    (CI)            │  dev             │  staging          ▲
                    └──────────────────┴──────────────────┘ back-merge
                                                    
hotfix/1.2.1 ──PR──► main ──tag v1.2.1──► prod, then back-merge to develop
```

This repository is built with that history rather than a single squashed
import: feature branches and merge commits are visible in
`git log --graph --decorate --all`. The release half of the flow is not yet
exercised: `base_version.json` is still `0.0.0` with `releasedTag: null`, no
`release/*` branch has been cut and no tag exists (verified with `git tag -l`).
The first release is the outstanding step, not a hidden one.

### 2.3 Why GitFlow here

- The assignment names GitFlow explicitly.
- The tag is the release artifact's permanent name. A reviewer can answer
  "what shipped?" with `git tag -l` and "what was in it?" with `git show v1.2.0`.
- `release/*` creates a stabilisation window that maps cleanly onto staging: the
  branch builds `rc` images, staging validates them, and `main` promotes exactly
  the tested commit.
- Trunk-based development with feature flags would be faster for a product team
  with continuous delivery, but it gives a weaker paper trail for a graded
  exercise and makes "which commit is production?" less obvious.

## 3. Semantic Versioning

### 3.1 What each number means in this product

| Change | Version bump | Example |
|---|---|---|
| Breaking API or configuration change; no rolling-back without a migration | MAJOR | `1.4.2` → `2.0.0` |
| New backwards-compatible endpoint or capability | MINOR | `1.4.2` → `1.5.0` |
| Backwards-compatible fix | PATCH | `1.4.2` → `1.4.3` |

Pre-release identifiers sort below the final release (`1.0.0-rc.2 < 1.0.0`).
Build metadata (`+<sha>`) is ignored for precedence, which is correct per
SemVer 2.0.0 and is why the commit SHA is also embedded in the image as
`GIT_SHA`.

### 3.2 Single source of truth: `base_version.json`

```json
{
  "major": 0,
  "minor": 0,
  "patch": 0,
  "releasedAt": null,
  "releasedTag": null
}
```

- It holds the **last released** version, never the version being built.
- Only a human or `scripts/release.sh` writes it. CI only reads it.
- No version literal is allowed anywhere else: the Jenkinsfile, Dockerfiles and
  manifests receive the value as build arguments or overlay edits.

### 3.3 Computed version per branch (`ci/scripts/version.py`)

| Branch / event | Computed version | `base_version.json` | Image pushed | Environment |
|---|---|---|---|---|
| `feature/*`, `fix/*`, `bugfix/*`, `chore/*`, `docs/*`, `refactor/*`, `test/*`, `dependabot/*` | `X.Y.(Z+1)-<slug>.N+<sha>` | unchanged | no | — |
| push `develop` | `X.Y.(Z+1)-dev.N+<sha>` | unchanged | yes | dev |
| `release/X.Y.Z` | `X.Y.Z-rc.N+<sha>` | unchanged | yes | staging |
| `hotfix/X.Y.Z` | `X.Y.Z-hotfix.N+<sha>` | unchanged | yes | staging |
| `main` + annotated tag `vX.Y.Z` | `X.Y.Z` | set to `X.Y.Z` | yes (`X.Y.Z` image tag; `vX.Y.Z` Git tag) | prod (manual sync) |
| detached HEAD | `0.0.0-local` | unchanged | no | — |
| any other branch name | refused (exit 1) | unchanged | no | — |

`N` is the Jenkins `BUILD_NUMBER`; `<sha>` is the 7-character commit SHA.
Feature branches use the **next** patch (`1.0.1-login-timeout.4`) rather than the
current one, so every build sorts above the most recent release tag.

### 3.4 Guard rails (they fail the build, they do not warn)

| Guard | Behaviour |
|---|---|
| Strict SemVer validation | A version that does not match the SemVer 2.0.0 grammar aborts the build |
| Monotonicity | The computed version must sort above the newest existing `v*` tag (`git tag --sort=-v:refname`) |
| Tagged main | A `main` build must carry a tag whose value equals `base_version.json`; an untagged production deploy is impossible once the project has a release |
| No literals | `base_version.json` is the only numeric source; `APP_VERSION` arrives as a Docker build argument |
| No mutable tags | The Jenkins `Preflight` stage greps overlays for `:latest` or `:local` and fails |
| Build identity | `APP_VERSION` and `GIT_SHA` are baked into the image and exposed by `GET /version` |

The policy itself is unit-tested: `ci/tests/test_version.py` covers branch
mapping, SemVer precedence, monotonicity and the `main`-must-be-tagged rule.

### 3.5 Who bumps the number, and when

The number is bumped **once per release, on `main`, by `scripts/release.sh`**.
Branches and commits never edit it. The release branch name and the bump
argument must describe the same version; `release.sh` does not read the branch,
so a mismatch is a human error the walkthrough in `docs/git-workflow.md` checks
for explicitly.

The table below assumes `base_version.json` is already `1.0.0`. On the first
run it is `0.0.0`, so the fix is `0.0.1-...` and `release.sh major` produces
`1.0.0` directly; the runbook uses exactly that sequence.

| Event | Version before | Action | Version after | Git tag |
|---|---|---|---|---|
| `fix/<name>` build | `1.0.0` | push the branch | `1.0.1-<slug>.N+<sha>` (not pushed) | none |
| merge the fix into `develop` | `1.0.0` | push `develop` | `1.0.1-dev.N+<sha>` → dev | none |
| cut `release/1.1.0` | `1.0.0` | create the branch | `1.1.0-rc.N+<sha>` → staging | none |
| merge the release into `main` | `1.0.0` | `./scripts/release.sh minor` | `1.1.0` (final) → prod | `v1.1.0` |
| emergency fix after the release | `1.0.0` | `hotfix/1.0.1` + `./scripts/release.sh patch` | `1.0.1` (final) → prod | `v1.0.1` |

Bump argument selection:

| Intended version | Release branch | `release.sh` argument |
|---|---|---|
| `1.1.0` (new feature) | `release/1.1.0` | `minor` |
| `1.0.1` (fix only) | `release/1.0.1` | `patch` |
| `2.0.0` (breaking) | `release/2.0.0` | `major` |

Three mechanical details that are easy to get wrong:

1. **The final build is a `main` branch build, not a tag build.** The Jenkins
   multibranch job discovers branches only. Pushing `main` together with the tag
   (`git push origin main --follow-tags`) triggers the `main` branch build; the
   tag is what lets `version.py` prove the commit is a real release via
   `git describe --exact-match --tags HEAD`. Pushing the tag alone builds
   nothing.
2. **The tag marks the source release commit, not the deployed digests.** After
   the build, CI pushes one more commit to `main`
   (`chore(gitops): pin X.Y.Z [skip ci]`) that writes the new image digests into
   `gitops/overlays/prod`. That commit is untagged by design. "What source
   shipped?" is the tag; "what bytes are running?" is the digest in the Argo CD
   synced revision.
3. **Back-merge immediately.** Until `main` (with the new
   `base_version.json`) is merged back into `develop`, develop builds compute
   from the old base and the monotonicity guard rejects them (for example
   `0.0.1-dev.N` does not sort above `v1.0.0`). For the same reason, stop
   building the release branch once it is tagged: `1.0.0-rc.N` sorts below
   `v1.0.0`.

## 4. Container image tagging policy

### 4.1 Tag grammar

| Build | Tag | Example | Mutable? |
|---|---|---|---|
| feature / fix / bugfix | `X.Y.(Z+1)-<slug>.N-<sha>` | `0.0.1-p4-jenkins.12-7d4e031` | no |
| develop | `X.Y.(Z+1)-dev.N-<sha>` | `0.0.1-dev.42-7d4e031` | no |
| release candidate | `X.Y.Z-rc.N-<sha>` | `1.0.0-rc.3-7d4e031` | no |
| hotfix | `X.Y.Z-hotfix.N-<sha>` | `1.0.1-hotfix.1-7d4e031` | no |
| final | `X.Y.Z` (Git tag is `vX.Y.Z`) | Git `v1.0.0`; image `1.0.0` | no (by policy) |

SemVer uses `+` for build metadata (`1.0.0-rc.3+7d4e031`); Docker tags cannot
contain `+`, so the tag replaces it with `-`. The authoritative version string
inside the image keeps the `+` and is what `/version` returns.

The Git tag carries the conventional `v` prefix (`v1.0.0`); the container tag is
the computed version without it (`1.0.0`). The pipeline pushes **one** tag per
build, not an additional `X.Y.Z-<sha>` tag: the digest written into the overlay
is the immutable identity, so repeating the short SHA in a tag adds no
information and one more moving part to prune.

### 4.2 Immutable tags versus `latest`

| | Immutable tag + digest pin | `latest` |
|---|---|---|
| Meaning | Exactly one set of bytes | Whatever was pushed most recently |
| Two nodes on the same tag | Always identical | Can differ if one cached an older pull |
| Rollback | Revert to a known digest | Guess which build "latest" was |
| Audit | Tag, digest and commit are recorded in Git and Argo CD | No reliable answer |
| Cache behaviour | Predictable | `imagePullPolicy: Always` required, and still racy |
| Recommendation | **Used everywhere in this repo** | **Forbidden** |

`latest` is not a version, it is a hope. The tag is only a human-friendly
pointer; the digest (`@sha256:…`) is the identity. All three overlays therefore
pin digests, for example:

```yaml
# gitops/overlays/prod/kustomization.yaml
images:
  - name: ghcr.io/danbarel78/bituach-yashir-engine
    digest: sha256:8cad16f7ca56644f45bf5bf2d6f4cc841d0b4c0c84276a3473b3256335878c05
```

The CI job pushes the tag, reads the registry digest with
`docker inspect --format '{{index .RepoDigests 0}}'`, and
`ci/scripts/gitops-update.sh` writes only the digest into the overlay. A tag
that is later moved cannot silently change what production runs.

### 4.3 Promotion path

```
build → tag → push to GHCR → digest → commit to overlay → Argo CD sync
```

| Step | Artifact | Who does it |
|---|---|---|
| Build | `APP_VERSION`, `GIT_SHA` build args | Jenkins `Build` |
| Push | `ghcr.io/danbarel78/bituach-yashir-<svc>:<tag>` | Jenkins `Push` (dev/staging/prod only) |
| Pin | `digest: sha256:…` in `gitops/overlays/<env>/kustomization.yaml` | `ci/scripts/gitops-update.sh` |
| Deploy | Argo CD reconciles the commit | Argo CD (`bituach-<env>` Application) |
| Verify | `/version` returns version + SHA + environment | `scripts/smoke-test.sh` |

Promotion never copies an image between environments. The same digest is
referenced by staging and prod; what changes is the Git commit that a human
approved.

### 4.4 Verification

```bash
# Which digest is running?
kubectl -n bituach-prod get deploy engine \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# What does the process believe it is?
curl -sk --resolve engine.bituach.localhost:443:127.0.0.1 \
  https://engine.bituach.localhost/version
# {"service":"engine","version":"0.0.1-dev.0+11e3604","gitSha":"11e3604","environment":"prod"}

# Registry truth, independent of the cluster
docker buildx imagetools inspect ghcr.io/danbarel78/bituach-yashir-engine:v1.0.0
```

### 4.5 Retention

Policy: keep the last three tags per service (GitHub Packages free quota is
500 MB). This is a policy statement today: the Jenkinsfile does **not** yet
contain an automated prune stage, and GHCR retention is manual. Adding a
`Retention` stage that lists package versions and deletes all but the newest
three is a known follow-up. Digests referenced by an overlay must never be
deleted, so pruning must exclude the three environments' current pins.

## 5. Changelog management

### 5.1 Commit convention

Every commit uses Conventional Commits:

```
<type>(<scope>): <summary>

<body: why, not what>

BREAKING CHANGE: <what breaks and the migration>
```

Types used in this repository: `feat`, `fix`, `chore`, `docs`, `refactor`,
`perf`, `test`, `ci`, `style`. `Merge …` commits are ignored by the generator.

### 5.2 Format and generation

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/). It is
**generated, not hand-edited**, by `scripts/release.sh`:

1. `git describe --tags --abbrev=0` finds the previous release.
2. Commits in `<last-tag>..HEAD` are grouped:
   - `feat` → Added
   - `fix` → Fixed
   - `perf`, `refactor` → Changed
   - `chore` → Chore
   - `BREAKING CHANGE:` footers → Breaking Changes
3. The new section is prepended; all earlier version sections are preserved.
4. The bump, the changelog and the annotated tag are committed together.

`CHANGELOG.md` exists in the repository with the pre-release baseline, so a
reviewer sees the format before the first release. Its `## [v0.0.0]` section
documents the POC as delivered; `scripts/release.sh` will prepend `v1.0.0`
above it.

### 5.3 Ownership

- Authors write good commit messages; that is the input.
- The release manager reviews the generated changelog diff during the release
  commit — it is a review artifact, not free text.
- The changelog describes **user-visible change**, not every commit. A `chore`
  entry is included for completeness but is not part of release notes.

## 6. Kubernetes rollout strategy

### 6.1 Implemented: Rolling Update

All three services declare the same strategy in `gitops/base/*/deployment.yaml`:

```yaml
spec:
  replicas: 1                 # overridden per overlay: 1 / 2 / 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1             # one extra pod may exist during the rollout
      maxUnavailable: 0       # capacity never drops below the desired count
```

Why this shape:

- `maxUnavailable: 0` means a new pod must exist **and pass its readiness
  probe** before an old one is terminated. On a single-node POC that is the
  difference between "zero downtime" and "one replica restarts while the only
  other one is not ready".
- `maxSurge: 1` bounds the extra capacity to one pod per service, which matters
  under the namespace `ResourceQuota` and on a single node.
- Readiness (`/readyz`) checks the downstream services, so a pod that cannot
  reach `data` or `ingest` never receives traffic.
- `startupProbe` gives a cold start up to 60 s before liveness begins counting,
  avoiding a restart loop on a loaded laptop.
- The rollout is driven by Argo CD: the digest change is the trigger, and
  Argo CD's application health reflects the Deployment's rollout status.

Rollback is the same mechanism in reverse: `git revert` the overlay commit and
let Argo CD reconcile (prod: approve the sync). There is no imperative
`kubectl rollout undo` in the runbook, because that would create state that Git
does not know about.

### 6.2 Alternatives considered

**Blue-Green** — two identical stacks (`blue` = current, `green` = next). A
Service selector or Ingress backend switch moves 100% of traffic at once.

```yaml
# sketch: the cutover is one label change on the Service selector
selector:
  app.kubernetes.io/name: engine
  track: green        # was "blue"
```

| Pros | Cons |
|---|---|
| Instant, atomic switch and instant rollback (switch back) | Doubles the resource footprint for the duration |
| Easy to smoke-test the new stack before cutover | Database/schema changes still need backward compatibility |
| Clear "which stack is live?" answer | Needs a controller or a second Deployment + Service pair per service |

**Canary** — send a small share of traffic to the new version, watch error rate
and latency, then increase. With Argo Rollouts this is a `Rollout` resource with
`setWeight` steps and an `AnalysisTemplate` querying Prometheus.

```yaml
# sketch: 5% -> 25% -> 50% -> 100%, abort on error-rate breach
strategy:
  canary:
    steps:
      - setWeight: 5
      - pause: { duration: 2m }
      - analysis:
          templates: [{ templateName: error-rate }]
      - setWeight: 25
      - pause: { duration: 5m }
      - setWeight: 100
```

| Pros | Cons |
|---|---|
| Smallest blast radius; real user traffic validates the change | Requires traffic splitting and reliable metrics/analysis |
| Automatic abort on SLO breach | More moving parts; not useful without the observability stack |
| Best fit for high-traffic production services | A canary of 5% is meaningless at POC traffic levels |

### 6.3 Comparison and decision

| Criterion | Rolling Update (used) | Blue-Green | Canary |
|---|---|---|---|
| Downtime | None with probes | None | None |
| Extra resources | 1 pod per service | 100% duplicate stack | A fraction of replicas |
| Blast radius of a bad release | All new pods, gradually | All traffic after switch | Small percentage first |
| Rollback speed | Revert Git → rollout | Instant selector switch | Abort + automatic revert |
| Operational complexity | Low (native) | Medium | High (controller + analysis) |
| Needs metrics | Readiness only | Smoke tests | Yes, SLO-grade metrics |
| Fit for this POC | **Yes** | Overkill | Overkill (no traffic, no Prometheus) |

**Decision:** Rolling Update is the deployed strategy for dev, staging and
prod. Blue-green and canary are documented as the production evolution, with
Argo Rollouts as the migration path; canary is the first choice once a
Prometheus/Grafana stack exists, and blue-green is reserved for releases with
risky schema or dependency changes. Mixing strategies per service is allowed —
the strategy lives in the Deployment/Rollout object, not in the pipeline.

Database compatibility rule for any future strategy: every release must run
against the previous release's schema (expand/contract migrations) so two
versions can coexist during a rollout.

## 7. Evidence and known gaps

| Claim | Evidence | Status |
|---|---|---|
| GitFlow branches exist | `git branch -a`, merge commits in `git log --graph` | implemented |
| SemVer engine + guard rails | `ci/scripts/version.py`, `ci/tests/test_version.py` | implemented |
| No `latest` in overlays | Jenkins `Preflight`; `gitops/overlays/*/kustomization.yaml` | implemented |
| Digest-pinned deployments | overlays render `ghcr.io/...@sha256:…` | implemented |
| `/version` reports build identity | service endpoint, smoke test | implemented |
| RollingUpdate with zero-downtime settings | `gitops/base/*/deployment.yaml` | implemented |
| Changelog generation | `scripts/release.sh`, `CHANGELOG.md` | implemented (baseline) |
| Full developer→prod runbook | `docs/git-workflow.md` | documented; first execution pending |
| Argo CD promotion wiring | dev/staging track `develop`; prod tracks `main` after the first release | implemented (first-release cutover) |
| First real release `v1.0.0` | `base_version.json` still `0.0.0`, no tags | **not done** |
| Automated tag retention (last 3) | no Jenkins stage | **not done** |
| Canary / blue-green | design in §6.2 | documented only |
