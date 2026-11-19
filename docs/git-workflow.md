# Git workflow, versioning and the CI pipeline

This document is the operational companion to `handoff.md` (decisions) and
`docs/review-and-walkthrough.md` (walkthrough). It describes how a change goes
from a branch to an environment, and how to run the same steps by hand.

## 1. Branch model (GitFlow)

| Branch | Purpose | Lifetime |
|---|---|---|
| `main` | released code; every commit carries a `vX.Y.Z` tag | permanent |
| `develop` | integration of finished features | permanent |
| `feature/*` | one change, PR into `develop` | deleted after merge |
| `release/X.Y.Z` | stabilisation and release candidate builds | deleted after release |
| `hotfix/X.Y.Z` | urgent fix cut from a release tag | deleted after merge |

`main` and `develop` are protected: changes arrive through a pull request, and
only the release manager merges into `main`.

## 2. Branch → version → environment

| Branch | Computed version | Image pushed | Environment | Approval |
|---|---|---|---|---|
| `feature/*` `bugfix/*` `chore/*` `docs/*` `refactor/*` `test/*` `dependabot/*` | `X.Y.(Z+1)-<slug>.<n>+<sha>` | no | — | — |
| `develop` | `X.Y.(Z+1)-dev.<n>+<sha>` | yes | dev | automatic (Argo CD) |
| `release/X.Y.Z` | `X.Y.Z-rc.<n>+<sha>` | yes | staging | automatic (Argo CD) |
| `hotfix/X.Y.Z` | `X.Y.Z-hotfix.<n>+<sha>` | yes | staging | automatic |
| `main` + `vX.Y.Z` tag | `X.Y.Z` | yes | prod | **manual Argo CD sync** |
| detached HEAD | `0.0.0-local` | no | — | — |
| unknown named branch | refused | — | — | — |

`<n>` is the Jenkins build number, `<sha>` the 7-character commit.

The numeric version is **not** bumped by commits. It changes only when a
release is cut (`scripts/release.sh` on `main`); see §5.

## 3. Local quality gates

From the repository root:

```bash
make lint          # ruff check + format check, all services
make typecheck     # mypy, all services
make test          # pytest with coverage floor (80%)
make security      # bandit
python3 ci/scripts/version.py          # the version for the current branch
python3 -m pytest ci/tests -q          # the version policy itself
```

In WSL/CI the same commands run under `uv`, so the toolchain is identical to
the pipeline's.

## 4. Running the Jenkins pipeline

### 4.1 First start

```powershell
pwsh ./ci/jenkins.ps1 build      # build the controller image (~3 min)
pwsh ./ci/jenkins.ps1 up         # http://localhost:8080, admin / admin
pwsh ./ci/jenkins.ps1 status
pwsh ./ci/jenkins.ps1 logs
```

The container gets:

- the host Docker socket (it builds and pushes using the host daemon);
- a **generated** kubeconfig that points at `host.docker.internal` and pins the
  TLS name to `localhost` (Docker Desktop's API certificate has no
  `host.docker.internal` SAN). The file lives in `%TEMP%` and is never
  committed;
- a named volume `bituach-jenkins-home` for jobs, credentials and caches.

`JENKINS_ADMIN_PASSWORD` overrides the default `admin`.

### 4.2 Credential (one required secret)

The pipeline needs one credential, created **in the UI**, never in Git:

1. Create a classic PAT with exactly `repo` and `write:packages`.
2. Jenkins → **Manage Jenkins → Credentials → System → Global credentials**.
3. Add **Username with password**:
   - ID: `github-token`
   - Username: `danbarel78`
   - Password: the PAT

It is used twice: `docker login ghcr.io` and the `git push` of the GitOps
commit. It is consumed only inside `withCredentials`, and Jenkins masks its
value in the console.

### 4.3 Triggering

- The multibranch job `bituach-yashir` polls every minute per branch, and the
  folder indexes every five minutes.
- Push a branch → the build appears under that branch.
- Manual: **Scan Multibranch Pipeline Now**, then **Build Now**.

### 4.4 What the stages do

`Preflight` (skip-ci guard + no mutable tags) → `Version` → `Setup` → `Lint` →
`Types` → `Test` → `SAST` → `Dependencies` → `Build` → `Image scan` → `Push`
(branch-gated) → `GitOps` (branch-gated) → `Wait for Argo CD` (dev/staging) →
`Smoke` (dev/staging) → `Prod handoff` (tags).

Artifacts: `reports/` (bandit, requirements, Trivy) and `digests.txt`.

## 5. Cutting a release

```bash
git checkout develop && git pull --ff-only
git checkout -b release/1.0.0              # the version you intend to ship
# validation happens on this branch; rc images go to staging
git commit ... && git push origin release/1.0.0
# open a PR into main, merge it
git checkout main && git pull --ff-only
./scripts/release.sh major                 # patch | minor | major
git push origin main --follow-tags         # tag + release commit together
git checkout develop && git merge main && git push origin develop
```

Notes:

- `release.sh` refuses to run outside `main`.
- Push `main` **after** `release.sh`. An untagged `main` commit fails on
  purpose: production must be tagged.
- The push of the tag is the event that builds the final artifact.
- Prod then shows `OutOfSync` in Argo CD until a human clicks **Sync**.

## 6. Promotion and rollback

Promotion is a Git change, never a `kubectl` command:

| From → to | Mechanism |
|---|---|
| feature → develop | pull request |
| develop → staging | merge into `release/X.Y.Z` |
| staging → prod | merge into `main`, tag `vX.Y.Z` |
| prod rollback | `git revert` the overlay commit, then approve the sync |
| dev/staging rollback | `git revert`; Argo CD self-heals automatically |

The pipeline writes the digest into `gitops/overlays/<env>/kustomization.yaml`
in a commit marked `[skip ci]`, so it never triggers itself. If two builds
finish together, the script rebases and retries up to three times.

## 7. Troubleshooting

| Symptom | Check |
|---|---|
| Build runs but `Push` is skipped | branch is not `develop`/`release/*`/tagged `main` — expected |
| `unsupported branch name` | rename the branch to a supported prefix (§2) |
| `main builds must come from a tag` | run `release.sh`, push the tag with the commit |
| `git push` fails with 403 | `github-token` missing, expired, or lacks `repo` |
| `docker push` fails with 401 | token lacks `write:packages`, or the package is private |
| Argo CD stays `OutOfSync` | prod is manual by design; click Sync |
| Smoke fails from Jenkins only | `SMOKE_RESOLVE_IP` / `host.docker.internal` resolution |
| Jenkins cannot reach the cluster | regenerate the kubeconfig via `jenkins.ps1 up` |

## 8. Repository protection

- `main`: PR required, no direct pushes, tag on release.
- `develop`: PR required; CI must be green.
- The CI credential can write only through the pipeline; it is a classic PAT
  (`repo` scope), which is broader than ideal. The production improvement is a
  deploy key or a fine-grained token limited to this repository.