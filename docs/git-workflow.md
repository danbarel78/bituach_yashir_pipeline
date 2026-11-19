# Git workflow, versioning and the CI pipeline

This document is the operational companion to `handoff.md` (decisions),
`docs/versioning.md` (policy) and `docs/review-and-walkthrough.md`
(walkthrough). It describes how a change goes from a developer branch to
production, and how to run every step by hand.

The complete developer-to-production walkthrough is **§9**. Sections 1–8 are the
reference material it relies on.

## 1. Branch model (GitFlow)

| Branch | Purpose | Lifetime |
|---|---|---|
| `main` | released code; every release commit carries a `vX.Y.Z` tag | permanent |
| `develop` | integration of finished features | permanent |
| `feature/*` | one change, PR into `develop` | deleted after merge |
| `fix/*` | a bug fix, PR into `develop` (`bugfix/*` is an accepted alias) | deleted after merge |
| `release/X.Y.Z` | stabilisation and release candidate builds | deleted after release |
| `hotfix/X.Y.Z` | urgent fix cut from a release tag | deleted after merge |

`main` and `develop` are protected: changes arrive through a pull request, and
only the release manager merges into `main`. The pipeline itself writes digest
commits to `develop` and `main`; the CI credential must therefore be allowed to
push there (see §8).

## 2. Branch → version → environment

| Branch | Computed version | Image pushed | Environment | Approval |
|---|---|---|---|---|
| `feature/*` `fix/*` `bugfix/*` `chore/*` `docs/*` `refactor/*` `test/*` `dependabot/*` | `X.Y.(Z+1)-<slug>.<n>+<sha>` | no | — | — |
| `develop` | `X.Y.(Z+1)-dev.<n>+<sha>` | yes | dev | automatic (Argo CD) |
| `release/X.Y.Z` | `X.Y.Z-rc.<n>+<sha>` | yes | staging | automatic (Argo CD) |
| `hotfix/X.Y.Z` | `X.Y.Z-hotfix.<n>+<sha>` | yes | staging | automatic |
| `main` at a `vX.Y.Z` tag | `X.Y.Z` | yes | prod | **manual Argo CD sync** |
| detached HEAD | `0.0.0-local` | no | — | — |
| unknown named branch | refused | — | — | — |

`<n>` is the Jenkins build number, `<sha>` the 7-character commit.

The numeric version is **not** bumped by commits. It changes only when a
release is cut (`scripts/release.sh` on `main`); see §5 and `docs/versioning.md`
§3.5.

Two naming rules that cause avoidable build failures:

- The branch must start with a supported prefix. `fix/` was added as an alias of
  `bugfix/`; a branch named only `delta-value` is rejected.
- `release/` and `hotfix/` must be followed by a full `X.Y.Z` version, because
  the branch name is the version for those two variants.

## 3. Local quality gates

From the repository root (WSL Ubuntu recommended, because the scripts are bash):

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

1. Create a classic PAT with `repo` and `write:packages`.
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
- **Tags are not discovered as separate builds.** The release build is the
  `main` branch build at the tagged commit; the tag is pushed together with
  `main` and `version.py` verifies it.
- Manual: **Scan Multibranch Pipeline Now**, then **Build Now**.

### 4.4 What the stages do

`Preflight` (skip-ci guard + no mutable tags) → `Version` (fetches tags, computes
the version) → `Setup` → `Lint` → `Types` → `Test` → `SAST` → `Dependencies` →
`Build` → `Image scan` → `Push` (branch-gated) → `GitOps` (branch-gated) →
`Wait for Argo CD` (dev/staging) → `Smoke` (dev/staging) → `Prod handoff`
(main).

Artifacts: `reports/` (bandit, requirements, Trivy) and `digests.txt`.

## 5. Cutting a release

The bump is a deliberate, visible act. The release branch says **what** is being
released; `release.sh` makes it official and creates the tag.

```bash
# 1. cut the release branch from the integration branch
git checkout develop && git pull --ff-only
git checkout -b release/1.0.0            # must match the intended version
git push -u origin release/1.0.0

# 2. after staging validation, merge into main (PR in GitHub; CLI equivalent)
git checkout main && git pull --ff-only
git merge --no-ff release/1.0.0 -m "Merge branch 'release/1.0.0' into main"

# 3. bump + tag. The argument MUST match the branch:
#      release/1.0.0 -> major (from 0.0.0)      -> v1.0.0
#      release/1.1.0 -> minor                  -> v1.1.0
#      release/1.0.1 -> patch                  -> v1.0.1
./scripts/release.sh major

# 4. push the release commit and the tag together
git push origin main --follow-tags

# 5. back-merge immediately (see the warning below)
git checkout develop && git merge --no-ff main && git push origin develop
```

Expected output from `release.sh`:

```
==> bumped base_version.json to v1.0.0
==> regenerated CHANGELOG.md
[main 4f2c1ab] chore(release): v1.0.0
==> Release v1.0.0 created locally. Push manually (no `gh` CLI):

    git push origin main --follow-tags

    # back-merge main into develop (GitFlow step 5):
    git checkout develop && git merge main && git push origin develop
```

Verify **before** pushing:

```bash
git describe --exact-match --tags HEAD   # v1.0.0
git tag -l                               # v1.0.0
cat base_version.json                    # major 1, minor 0, patch 0, releasedTag "v1.0.0"
git show --stat HEAD                     # changes base_version.json and CHANGELOG.md only
```

Notes:

- `release.sh` refuses to run outside `main`. It commits only
  `base_version.json` and `CHANGELOG.md`, but start from a clean tree so the
  release commit contains exactly those two files.
- Push `main` **after** `release.sh`. An untagged `main` commit fails on purpose:
  production must be tagged.
- Pushing `main` is what triggers the build; pushing the tag alone builds
  nothing. Pushing both together is required: `main` triggers, the tag is the
  proof.
- Prod then shows `OutOfSync` in Argo CD until a human clicks **Sync**.
- **Back-merge immediately.** Once `v1.0.0` exists, a `develop` build running
  with the old `base_version.json` (0.0.0) computes `0.0.1-dev.N`, which sorts
  below `v1.0.0`, and the monotonicity guard fails the build. The back-merge
  brings `base_version.json` = 1.0.0 to `develop`, and the next build is
  `1.0.1-dev.N`. For the same reason, do not build the release branch after it
  has been tagged (`1.0.0-rc.N` < `v1.0.0`).

## 6. Promotion and rollback

Promotion is a Git change, never a `kubectl` command:

| From → to | Mechanism |
|---|---|
| feature/fix → develop | pull request |
| develop → staging | merge into `release/X.Y.Z` |
| staging → prod | merge into `main`, tag `vX.Y.Z` |
| prod rollback | `git revert` the overlay commit, then approve the sync |
| dev/staging rollback | `git revert`; Argo CD self-heals automatically |

The pipeline writes the digest into `gitops/overlays/<env>/kustomization.yaml`
in a commit marked `[skip ci]`, so it never triggers itself. If two builds
finish together, the script rebases and retries up to three times.

**Promotion wiring in the POC.** The three Argo CD Applications currently all
track `develop`; that is enough to demonstrate three environments from one
commit, but not enough for a real promotion. For the walkthrough in §9 the
staging Application must track the active `release/*` (or `hotfix/*`) branch and
the prod Application must track `main`. Because `bituach-root` self-heals the
Application manifests, these retargets are **commits to Git**, not `kubectl
patch` commands; §9.1 gives the exact edits. Permanent promotion wiring is a
known P6 item.

## 7. Troubleshooting

| Symptom | Check |
|---|---|
| Build runs but `Push` is skipped | branch is not `develop`/`release/*`/`hotfix/*`/tagged `main` — expected |
| `unsupported branch name` | rename the branch to a supported prefix (§2); `fix/` is supported |
| `main builds must come from a tag` | run `release.sh`, and push `main` with `--follow-tags` |
| `version ... does not sort above newest existing tag` | the tag exists but `base_version.json` was not bumped, or develop was not back-merged (§5) |
| `release branch must be named release/X.Y.0` | include all three numbers, e.g. `release/1.0.0` |
| `git push` fails with 403 | `github-token` missing/expired, lacks `repo`, or main protection blocks the bot |
| `docker push` fails with 401 | token lacks `write:packages`, or the package is private |
| Argo CD stays `OutOfSync` | prod is manual by design; click Sync |
| Argo CD shows `Unknown` / `path does not exist` | the Application tracks a branch that does not exist (release branch deleted) or lacks the overlay; retarget it (§9.1) |
| Smoke fails from Jenkins only | `SMOKE_RESOLVE_IP` / `host.docker.internal` resolution |
| Jenkins cannot reach the cluster | regenerate the kubeconfig via `jenkins.ps1 up` |

## 8. Repository protection

- `main`: PR required, no direct pushes, tag on release.
- `develop`: PR required; CI must be green.
- The pipeline pushes digest commits to both branches, so the `github-token`
  identity must be allowed to bypass the PR rule (repository admin / bypass
  list). If it is not, the `GitOps` stage fails with 403 and the overlay is
  never updated. Decide this before running §9.
- The CI credential is a classic PAT (`repo` scope), which is broader than
  ideal. The production improvement is a deploy key or a fine-grained token
  limited to this repository.

---

## 9. Developer change → production, step by step

This is the full manual simulation. It uses a deliberately small, observable
change so every stage can be verified with one HTTP call. The example is a data
correction in the `data` service:

```python
# services/data/src/data/services/item_catalog.py
-    Item(id=4, name="Delta Claim", category="claim", value=99.99),
+    Item(id=4, name="Delta Claim", category="claim", value=89.99),
```

The expected visible result is `"value":89.99` for item 4 at every environment.
Substitute any change you like; the version mechanics do not depend on the
service.

**Execution checklist**

- [ ] Pre-flight Phases 0–6 green (§9.1).
- [ ] Pending changes committed and pushed (docs, `fix/` support, tag fetch).
- [ ] Jenkins branch filter allows `fix/*`, or use `bugfix/*`.
- [ ] `main` protection lets `github-token` push the digest commit.
- [ ] `fix/*` build green with `Push` skipped.
- [ ] `develop` build deploys dev; smoke 9/9; value changed.
- [ ] `release/1.0.0` build deploys staging; staging retargeted; smoke 9/9.
- [ ] `v1.0.0` tagged; `main` build pins prod; prod retargeted; manual Sync.
- [ ] Prod `/version` = `1.0.0`, value changed, 6 pods Ready.
- [ ] Back-merge to `develop`; staging retargeted to `main`; release deleted.
- [ ] Hotfix path repeated for `v1.0.1` (optional).

### 9.1 Pre-flight — complete every phase before step 1

These are go/no-go checks. Re-run them immediately before the simulation; the
observed values below are from **2026-11-19** on this machine. Commands marked
*read-only* change nothing. Do not start §9.2 until every gate in Phase 6 is
green.

#### Phase 0 — freeze and snapshot the baseline (read-only)

Announce a short freeze: no one pushes to `develop` or `main` while the
simulation runs, otherwise the build numbers and sync revisions become
ambiguous.

```powershell
git status --short
git rev-parse --short HEAD
git tag -l
git ls-remote --heads origin
kubectl get nodes
kubectl -n argocd get applications
kubectl -n argocd get applications -o custom-columns='NAME:.metadata.name,TRACKS:.spec.source.targetRevision,PATH:.spec.source.path,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Observed baseline on 2026-11-19:

| Item | Baseline |
|---|---|
| Node | `desktop-control-plane   Ready` |
| Argo apps | `bituach-dev/staging/prod/root` all `Synced/Healthy` |
| Target revisions | all four track `develop` |
| `develop` HEAD | `82cb5cb` (`docs: record P4 completion…`) |
| `main` HEAD | `433f9ac` (scaffold only — no Jenkinsfile/overlays) |
| Tags | none (`git tag -l` empty) |
| dev | `0.0.1-dev.5+877242a` |
| staging | `0.0.1-dev.0+11e3604` |
| prod | `0.0.1-dev.0+11e3604` |
| dev `data` item 4 | `"value":99.99` (4 items) |
| prod digests (rollback target) | `engine 8cad16f…`, `data 26e14ab…`, `ingest 0f8239d…` |
| Jenkins builds | `develop` #5, `feature/p4-jenkins` #10 |

Capture the three `/version` responses and the `data` `/items` response as
"before" evidence:

```powershell
curl.exe -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 https://engine.dev.bituach.localhost/version
curl.exe -sk --resolve engine.staging.bituach.localhost:443:127.0.0.1 https://engine.staging.bituach.localhost/version
curl.exe -sk --resolve engine.bituach.localhost:443:127.0.0.1 https://engine.bituach.localhost/version
curl.exe -sk --resolve data.bituach.localhost:443:127.0.0.1 https://data.bituach.localhost/items
```

#### Phase 1 — land the pending changes (this is a write phase)

The runbook, `fix/` support and the tag fetch are **uncommitted by design**.
Jenkins reads the Jenkinsfile and scripts from the branch, so they must be on
`develop` before the simulation. Split them into reviewable commits:

```bash
git checkout develop && git pull --ff-only
git checkout -b chore/e2e-preflight

# 1. documentation + changelog baseline
git add docs/versioning.md docs/secrets.md docs/environment-topology.md docs/requirements-coverage.md docs/git-workflow.md handoff.md CHANGELOG.md
git commit -m "docs: add versioning, secrets, topology and developer-to-prod runbook"

# 2. fix/ support + fetch tags for the release build
git add ci/scripts/version.py ci/tests/test_version.py ci/docker/jenkins/init.groovy.d/01-multibranch.groovy ci/Jenkinsfile
git commit -m "feat(ci): accept fix/* branches and fetch tags for release builds"

# 3. release.sh clean-tree guard
git add scripts/release.sh
git commit -m "fix(release): require a clean working tree"

git push -u origin chore/e2e-preflight
```

Open a PR into `develop` in the GitHub UI and merge it. Expected: the develop
build runs the full pipeline, pushes `0.0.1-dev.<M>-<sha>`, pins the dev
overlay, and smoke passes **9/9**. This proves the pipeline is healthy before the
demo starts.

Then update the local integration branch:

```bash
git checkout develop && git pull --ff-only
git status --short          # expected: clean
python3 ci/scripts/version.py
# 0.0.1-dev.0+<sha>   locally; CI uses BUILD_NUMBER
```

> The docs commit is harmless, but it does produce a new dev image. That is
> expected and gives you a fresh build number for the run.

#### Phase 2 — make the running Jenkins job accept `fix/*`

The live job was created with the old filter. Verified on 2026-11-19, its
config still contains:

```
^(develop|main|release/.+|hotfix/.+|feature/.+|bugfix/.+|chore/.+|docs/.+|refactor/.+|test/.+|dependabot/.+)$
```

That regex has **no `fix/`**, so a literal `fix/...` branch will never appear as
a job. Choose one:

**Option A (zero Jenkins changes, recommended for this run):** use
`bugfix/delta-value` instead of `fix/delta-value`. The computed version is
identical (`0.0.1-delta-value.<N>+<sha>`), and every later step is unchanged.

**Option B (use literal `fix/`):** open Jenkins →
`bituach-yashir` → **Configure** → **Branch Sources** → **Git** → the
**Filter by name (with regular expression)** behaviour, and replace the regex
with:

```
^(develop|main|release/.+|hotfix/.+|feature/.+|fix/.+|bugfix/.+|chore/.+|docs/.+|refactor/.+|test/.+|dependabot/.+)$
```

Save, then **Scan Multibranch Pipeline Now**. Rebuilding the controller image is
**not** enough: `01-multibranch.groovy` leaves an existing job untouched.

Verify the running job config (read-only):

```powershell
$h = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('admin:admin'))}
(Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8080/job/bituach-yashir/config.xml' -Headers $h).Content |
  Select-String 'regex'
```

Expected: the `<regex>` line contains `fix/.+`.

Two related facts to expect:

- There is currently **no `main` job** under `bituach-yashir` (the branch has no
  Jenkinsfile). After the release merge it appears on the next folder scan, or
  after **Scan Multibranch Pipeline Now**.
- On this machine `pwsh` is not installed; use
  `powershell -NoProfile -ExecutionPolicy Bypass -File .\ci\jenkins.ps1 status`
  (verified working) or install PowerShell 7.

#### Phase 3 — credentials, push rights, and WSL identity

**Jenkins credential.** Verified present:

```powershell
$h = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('admin:admin'))}
(Invoke-RestMethod -Uri 'http://localhost:8080/credentials/store/system/domain/_/api/json?tree=credentials[id,typeName]' -Headers $h).credentials
```

Expected: `github-token  Username with password`. In GitHub, confirm the PAT is
not expired and still has `repo` + `write:packages`.

**Main branch protection.** The release build pushes
`chore(gitops): pin 1.0.0 [skip ci]` directly to `main`. In GitHub →
**Settings → Branches → `main`**, confirm one of:

- the `github-token` identity (or the repository admin) is in the bypass list;
- direct pushes are temporarily allowed for the simulation, to be restored
  afterwards.

If neither is true, the `GitOps` stage fails with **403** after the images are
pushed, and prod never receives the pin. P4 only proved the `develop` push;
`main` is untested.

**Jenkins can reach the cluster** (read-only):

```powershell
docker exec bituach-jenkins kubectl get nodes
```

Expected: `desktop-control-plane   Ready`. If not, re-run
`powershell -File .\ci\jenkins.ps1 up` to regenerate the kubeconfig.

**WSL git identity.** `scripts/release.sh` runs in WSL and commits the bump and
the tag. Verified on 2026-11-19: WSL has **no** `user.name`/`user.email`, so the
release commit would fail with "empty ident". Configure it once (this writes the
repository-local config, which Windows also sees):

```powershell
wsl -d Ubuntu -- bash -lc 'cd /mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline && git config user.name "Daniel Barel" && git config user.email "dbarel@gmail.com" && git config user.name && git config user.email'
```

Expected: the two values echoed back. Also verify the script and the Python:

```powershell
wsl -d Ubuntu -- bash -lc 'cd /mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline && bash -n scripts/release.sh && python3 ci/scripts/version.py'
```

Expected: no bash errors; `0.0.1-dev.0+<sha>`.

**GHCR image is reachable** (read-only, proven in P4):

```powershell
docker buildx imagetools inspect ghcr.io/danbarel78/bituach-yashir-engine:0.0.1-dev.5-877242a
```

Expected: `Digest: sha256:ef4996d0…` and a `linux/amd64` manifest.

#### Phase 4 — confirm the Argo CD wiring and rollback baseline (read-only)

Expected today (verified): all four Applications track `develop`, dev/staging
have automated prune + self-heal, and prod has **no** `automated` sync block.
The two retarget points are deliberate and happen during the walkthrough:

| Point | Application | New revision | When |
|---|---|---|---|
| A | `bituach-staging` | `release/1.0.0` (or `hotfix/1.0.1`) | after the release branch is pushed, before staging validation |
| B | `bituach-prod` | `main` | after the release merge creates the prod overlay on `main` |

Because `bituach-root` self-heals the Application manifests, both are **Git
commits with `[skip ci]`**, not `kubectl patch`. Do **not** retarget prod before
the merge: `main` has no `gitops/overlays/prod` yet and the app would report
`path does not exist`.

Check the root sync and force a refresh if needed:

```powershell
kubectl -n argocd get application bituach-root
kubectl -n argocd annotate application bituach-root argocd.argoproj.io/refresh=normal --overwrite
```

Rollback baseline to keep for the end of the run: prod currently runs
`0.0.1-dev.0+11e3604` with digests `8cad16f…` (engine), `26e14ab…` (data),
`0f8239d…` (ingest). A rollback is a `git revert` of the pin commit plus a
manual Sync (§9.6).

#### Phase 5 — environment, tooling and budget

```powershell
$repo = '/mnt/c/Users/dbarel/OneDrive/Documents/MyProjects/bituach_yashir_demo/bituach_yashir_pipeline'
kubectl get nodes
wsl -d Ubuntu -- bash -lc "cd $repo && ./scripts/verify.sh"
wsl -d Ubuntu -- bash -lc "cd $repo && ./scripts/smoke-test.sh --env dev"
wsl -d Ubuntu -- bash -lc "cd $repo && ./scripts/smoke-test.sh --env staging"
wsl -d Ubuntu -- bash -lc "cd $repo && ./scripts/smoke-test.sh --env prod"
```

Expected: `21/21 checks passed` and **9/9** smoke checks per environment.
Optionally run `make lint typecheck test` from the repository root; the Jenkins
pipeline will run them anyway. Check disk headroom for three new images
(~57 MB each) with `docker system df`.

Time budget: **45–60 minutes** end to end, plus up to 5 minutes for the first
`main` folder scan and up to 3 minutes for an Argo CD poll.

#### Phase 6 — Go/No-Go gate

Do not create the fix branch until every row is true:

| # | Gate | Command | Expected |
|---|---|---|---|
| 1 | Cluster ready | `kubectl get nodes` | `Ready` |
| 2 | Platform healthy | `./scripts/verify.sh` | `21/21` |
| 3 | Four apps healthy | `kubectl -n argocd get applications` | `Synced/Healthy` |
| 4 | Pending changes merged | `git log --oneline -3 develop` | docs + CI commits present |
| 5 | Clean tree | `git status --short` | empty |
| 6 | Tags still absent | `git tag -l` | empty |
| 7 | Version computation | `python3 ci/scripts/version.py` | `0.0.1-dev.0+<sha>` locally |
| 8 | Jenkins filter | job `config.xml` regex | contains `fix/.+` **or** decision to use `bugfix/` |
| 9 | Credential | Jenkins credentials API | `github-token` present |
| 10 | Main write path | GitHub branch protection | bot/admin can push to `main` |
| 11 | Jenkins → cluster | `docker exec bituach-jenkins kubectl get nodes` | `Ready` |
| 12 | WSL identity | `git config user.email` (WSL) | non-empty |
| 13 | WSL release script | `bash -n scripts/release.sh` | no output |
| 14 | Argo baseline | apps table | dev/staging/prod track `develop` |
| 15 | Prod rollback target | `/version` prod | `0.0.1-dev.0+11e3604` |
| 16 | Demo change visible | `/items` | item 4 = `99.99` |
| 17 | Freeze respected | `git ls-remote` | unchanged during the run |

#### Phase 7 — abort plan before you need it

| Failure point | What is already true | Safe action |
|---|---|---|
| Fix/`bugfix` branch build red | Nothing pushed; no environment touched | Fix locally, amend or add a commit, push again |
| `develop` smoke fails | Only dev attempted | Do not cut the release; fix and push to `develop` |
| Staging smoke fails | Prod untouched | Fix on the release branch; do not merge to `main` |
| Main build fails **before** `GitOps` | Prod untouched; tag exists | Fix the cause and rerun the `main` build at the same tag (**Build Now**); do not move the tag |
| Main build fails **at** `GitOps` (403) | Images pushed; prod overlay unchanged | Fix branch protection, then rerun the same `main` build |
| Prod sync shows the wrong image | GitOps pin is a commit | `git revert` the pin with `[skip ci]`, push `main`, Sync again |
| Staging/prod tracks a deleted branch | Retarget commit pending | Revert the `[skip ci]` retarget commit, refresh the root app, then delete the branch |
| Tag was pushed with the wrong version | Published tag is immutable | Never force-move it; cut the next patch with `release.sh patch` |

Record the outcome of Phases 0–6 in the evidence table (§9.5) before starting
Step 1.


### 9.2 Path A — planned fix through dev, staging and prod

#### Step 1 — create the fix branch and make the change

```bash
git checkout develop
git pull --ff-only
git checkout -b fix/delta-value

# edit services/data/src/data/services/item_catalog.py (99.99 -> 89.99)
git diff -- services/data/src/data/services/item_catalog.py
git add -A
git commit -m "fix(data): correct the Delta Claim value"
```

Expected: `git diff` shows one changed line; the commit message is a Conventional
Commit (`fix:` feeds the changelog).

> If the running Jenkins job still filters only the original prefixes, use
> `bugfix/delta-value` instead. The computed version and every later step are
> identical; `fix/*` support is in the code and can be activated with the
> one-time filter refresh in §9.1.

Local check (optional but faster than a Jenkins round-trip):

```bash
python3 ci/scripts/version.py
```

Expected on `fix/delta-value` with `base_version.json` at 0.0.0:

```
0.0.1-delta-value.0+<sha>
```

The `0` is the local build number; CI replaces it with `BUILD_NUMBER`.

#### Step 2 — push the fix branch (proves the feature path, no deploy)

```bash
git push -u origin fix/delta-value
```

Jenkins discovers the new branch on the next folder scan (≤ 5 min) or after
**Scan Multibranch Pipeline Now**. Expected console line in the `Version` stage:

```
version=0.0.1-delta-value.<N>+<sha> tag=0.0.1-delta-value.<N>-<sha> branch=fix/delta-value sha=<sha> target=none
```

Expected result: **SUCCESS** with `Push`, `GitOps`, `Wait for Argo CD` and
`Smoke` all skipped. Nothing is published and no environment changes. This is
the gate that stops broken code from reaching a registry.

#### Step 3 — merge the fix into develop (deploys to dev)

Open a PR from `fix/delta-value` into `develop` in the GitHub UI and merge it
(no `gh` CLI). Locally:

```bash
git checkout develop
git pull --ff-only
```

Expected: the merge commit from the PR is on `develop`.

The push triggers a `develop` build. Expected `Version` line:

```
version=0.0.1-dev.<M>+<sha> tag=0.0.1-dev.<M>-<sha> branch=develop sha=<sha> target=dev
```

Expected stages after `Image scan`:

- `Push` logs three pushes and writes `digests.txt`.
- `GitOps` commits and pushes:

  ```
  chore(gitops): pin 0.0.1-dev.<M>+<sha> [skip ci]
  ```

  The commit changes only `gitops/overlays/dev/kustomization.yaml`.
- `Wait for Argo CD` ends with the pushed revision and `Synced/Healthy`.
- `Smoke` prints `All 9 smoke checks passed.`

Verify dev:

```powershell
curl.exe -sk --resolve data.dev.bituach.localhost:443:127.0.0.1 https://data.dev.bituach.localhost/items
curl.exe -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 https://engine.dev.bituach.localhost/version
kubectl -n argocd get application bituach-dev
```

Expected: the item 4 JSON contains `"value":89.99`; `/version` returns
`0.0.1-dev.<M>+<sha>`; the Application is `Synced/Healthy`.

> If the value is still 99.99, you are looking at a cached pod or the wrong
> digest. Compare the running image with the overlay:
> `kubectl -n bituach-dev get deploy data -o jsonpath='{.spec.template.spec.containers[0].image}'`.

#### Step 4 — cut the release branch and promote to staging

Only when dev is accepted:

```bash
git checkout develop && git pull --ff-only
git checkout -b release/1.0.0
git push -u origin release/1.0.0
```

Expected build console (release branch):

```
version=1.0.0-rc.<K>+<sha> tag=1.0.0-rc.<K>-<sha> branch=release/1.0.0 sha=<sha> target=staging
```

Expected: images pushed with tag `1.0.0-rc.<K>-<sha>`; the `GitOps` commit is on
`release/1.0.0` and pins the staging overlay; `Wait`/`Smoke` pass.

**Retarget staging to the release branch** (once per release). Edit
`gitops/argocd/apps/staging.yaml`:

```yaml
  source:
    repoURL: https://github.com/danbarel78/bituach_yashir_pipeline.git
    targetRevision: release/1.0.0     # was: develop
    path: gitops/overlays/staging
```

Commit and push on `develop`:

```bash
git checkout develop
git add gitops/argocd/apps/staging.yaml
git commit -m "chore(argocd): track release/1.0.0 in staging [skip ci]"
git push origin develop
```

`[skip ci]` is required: this is a platform config change, not an application
build. The root Application applies the retarget on its next sync (self-heal is
enabled, but Argo's default poll can take up to 3 minutes). To apply it
immediately:

```powershell
kubectl -n argocd annotate application bituach-root argocd.argoproj.io/refresh=normal --overwrite
```

Verify:

```powershell
kubectl -n argocd get application bituach-staging -o jsonpath='{.spec.source.targetRevision}{"\n"}'
# release/1.0.0

kubectl -n argocd get application bituach-staging
# NAME              SYNC STATUS   HEALTH STATUS
# bituach-staging   Synced        Healthy
```

Then verify the staging payload and version:

```powershell
curl.exe -sk --resolve data.staging.bituach.localhost:443:127.0.0.1 https://data.staging.bituach.localhost/items
curl.exe -sk --resolve engine.staging.bituach.localhost:443:127.0.0.1 https://engine.staging.bituach.localhost/version
```

Expected: item 4 is `89.99`; `/version` is `1.0.0-rc.<K>+<sha>`.

#### Step 5 — merge to main, tag, and release to production

```bash
git checkout main && git pull --ff-only
git merge --no-ff release/1.0.0 -m "Merge branch 'release/1.0.0' into main"
./scripts/release.sh major
```

Expected `release.sh` output: `==> bumped base_version.json to v1.0.0`,
`==> regenerated CHANGELOG.md`, a `chore(release): v1.0.0` commit, and the push
instructions. Verify as in §5:

```bash
git describe --exact-match --tags HEAD   # v1.0.0
cat base_version.json                    # major 1, minor 0, patch 0
git show --stat HEAD                     # base_version.json + CHANGELOG.md
```

Push the release commit and the annotation together:

```bash
git push origin main --follow-tags
```

The `main` branch build is the production artifact build. This is the first
`main` build that has a Jenkinsfile (the branch previously held only the
scaffold), so it may be picked up by the 5-minute folder scan rather than the
1-minute poll; use **Scan Multibranch Pipeline Now** if it does not start.
Expected `Version` console line:

```
version=1.0.0 tag=1.0.0 branch=main sha=<sha> target=prod
```

Expected stages:

- `Build`: image tag `1.0.0` (the Git tag is `v1.0.0`; the image tag is the
  version without the prefix).
- `Push`: three `1.0.0` images.
- `GitOps`: commit `chore(gitops): pin 1.0.0 [skip ci]` **on `main`**.
- `Wait for Argo CD` and `Smoke` are skipped for prod by design.
- `Prod handoff` prints:

  ```
  Prod overlay updated to 1.0.0 (1.0.0).
  Argo CD will show bituach-prod as OutOfSync; prod deploys only after a manual Sync.
  Approve at: http://argocd.localhost/applications/argocd/bituach-prod
  ```

**Retarget prod to `main`** (once, now that `main` contains the overlays):

```yaml
# gitops/argocd/apps/prod.yaml
  source:
    targetRevision: main              # was: develop
    path: gitops/overlays/prod
```

```bash
git checkout develop
git add gitops/argocd/apps/prod.yaml
git commit -m "chore(argocd): track main in prod [skip ci]"
git push origin develop
```

Refresh the root Application if you do not want to wait for the poll:

```powershell
kubectl -n argocd annotate application bituach-root argocd.argoproj.io/refresh=normal --overwrite
```

Verify that prod is now deliberately `OutOfSync`:

```powershell
kubectl -n argocd get application bituach-prod
# NAME           SYNC STATUS   HEALTH STATUS
# bituach-prod   OutOfSync     Healthy
```

Approve the production deploy, either in the UI (**bituach-prod → Sync**) or:

```powershell
kubectl -n argocd patch application bituach-prod --type merge -p '{"operation":{"sync":{"prune":false}}}'
```

Then verify:

```powershell
kubectl -n argocd get application bituach-prod          # Synced / Healthy
kubectl -n bituach-prod get deploy,pods
curl.exe -sk --resolve data.bituach.localhost:443:127.0.0.1 https://data.bituach.localhost/items
curl.exe -sk --resolve engine.bituach.localhost:443:127.0.0.1 https://engine.bituach.localhost/version
```

Expected: prod runs six pods (2 per service); item 4 is `89.99`; `/version`
returns `1.0.0` with `"environment":"prod"`; the Application is
`Synced/Healthy`.

**Back-merge and clean up** (do not skip the first command):

```bash
git checkout develop && git merge --no-ff main && git push origin develop
# base_version.json on develop is now 1.0.0; the next develop build is 1.0.1-dev.N

git push origin --delete release/1.0.0
```

Before deleting the release branch, retarget staging to `main` so it does not
point at a deleted ref:

```yaml
# gitops/argocd/apps/staging.yaml
targetRevision: main
```

```bash
git add gitops/argocd/apps/staging.yaml
git commit -m "chore(argocd): track main in staging after v1.0.0 [skip ci]"
git push origin develop
```

Expected: staging remains `Synced/Healthy` on the released image.

### 9.3 Path B — emergency hotfix from the release tag

Use this when production is broken and `develop` contains unreleased work.
The hotfix branch is cut from the **tag**, not from `develop`.

#### Step 1 — branch from the tag and fix

```bash
git fetch --tags
git checkout -b hotfix/1.0.1 v1.0.0

# make the smallest possible fix, e.g. item 3 value 450.75 -> 455.75
git add -A
git commit -m "fix(data): correct the Gamma Claim value"

python3 ci/scripts/version.py
# 1.0.1-hotfix.0+<sha>   (CI replaces 0 with BUILD_NUMBER)

git push -u origin hotfix/1.0.1
```

Expected Jenkins `Version` line:

```
version=1.0.1-hotfix.<J>+<sha> tag=1.0.1-hotfix.<J>-<sha> branch=hotfix/1.0.1 sha=<sha> target=staging
```

Expected: the same push/GitOps/smoke path as a release branch, but the version
is a `-hotfix.<J>` pre-release and the overlay commit lands on
`hotfix/1.0.1`.

**Retarget staging** to `hotfix/1.0.1` (same edit as §9.2 step 4, with the
hotfix branch):

```bash
git checkout develop
# edit gitops/argocd/apps/staging.yaml: targetRevision: hotfix/1.0.1
git add gitops/argocd/apps/staging.yaml
git commit -m "chore(argocd): track hotfix/1.0.1 in staging [skip ci]"
git push origin develop
```

Expected: staging syncs to the hotfix build; `/version` is
`1.0.1-hotfix.<J>+<sha>`; item 3 is `455.75`.

#### Step 2 — merge to main and cut the patch release

```bash
git checkout main && git pull --ff-only
git merge --no-ff hotfix/1.0.1 -m "Merge branch 'hotfix/1.0.1' into main"
./scripts/release.sh patch
```

Expected output: `==> bumped base_version.json to v1.0.1`; `git describe
--exact-match --tags HEAD` → `v1.0.1`; `base_version.json` patch = 1.

```bash
git push origin main --follow-tags
```

Expected `main` build: `version=1.0.1 tag=1.0.1 branch=main ... target=prod`;
image tag `1.0.1`; prod overlay pin commit on `main`; prod `OutOfSync`; manual
`Sync`; `/version` in prod = `1.0.1`; item 3 = `455.75`.

Then:

```bash
git checkout develop && git merge --no-ff main && git push origin develop
git push origin --delete hotfix/1.0.1
# retarget staging back to main (same commit as §9.2 cleanup)
```

### 9.4 Version and tag cheat sheet for the simulation

With `base_version.json` at 0.0.0 and no tags (today):

| Stage | Branch / ref | Computed version | Image tag | Git tag | Environment |
|---|---|---|---|---|---|
| fix pushed | `fix/delta-value` | `0.0.1-delta-value.<N>+<sha>` | not pushed | — | — |
| fix merged | `develop` | `0.0.1-dev.<M>+<sha>` | `0.0.1-dev.<M>-<sha>` | — | dev |
| release cut | `release/1.0.0` | `1.0.0-rc.<K>+<sha>` | `1.0.0-rc.<K>-<sha>` | — | staging |
| released | `main` @ tag | `1.0.0` | `1.0.0` | `v1.0.0` | prod |
| hotfix staged | `hotfix/1.0.1` | `1.0.1-hotfix.<J>+<sha>` | `1.0.1-hotfix.<J>-<sha>` | — | staging |
| hotfix released | `main` @ tag | `1.0.1` | `1.0.1` | `v1.0.1` | prod |

`N`, `M`, `K` and `J` are Jenkins build numbers. They are not a single counter:
each branch has its own build history. The numeric core (0.0.0 → 1.0.0 → 1.0.1)
changes only at `release.sh`.

### 9.5 Evidence to capture at each stage

| Stage | Evidence |
|---|---|
| fix branch | Jenkins build green; `Push` skipped; no new GHCR tag |
| dev | `chore(gitops): pin 0.0.1-dev.<M>+<sha> [skip ci]` commit; smoke 9/9; `/version`; item value |
| staging | `release/1.0.0` build; staging overlay digest; `Synced/Healthy`; `/version` `1.0.0-rc.<K>` |
| prod | `v1.0.0` tag; `chore(gitops): pin 1.0.0 [skip ci]` on `main`; prod App `OutOfSync` → manual Sync → `Synced`; 6 pods; `/version` `1.0.0`; item value |
| changelog | `git show v1.0.0:CHANGELOG.md` contains the fix under `## [v1.0.0]` |
| hotfix | same sequence with `v1.0.1`, `1.0.1`, and the corrected value |

### 9.6 Rollback drill (optional)

Rollback is a Git revert, not `kubectl rollout undo`. After the hotfix release
(§9.3), the previous release is `v1.0.0`:

```bash
git checkout main && git pull --ff-only
git log --oneline -5          # find the hotfix digest pin: chore(gitops): pin 1.0.1 [skip ci]
git revert --no-commit <that-commit>
git commit -m "revert(gitops): roll back prod to 1.0.0 [skip ci]"
git push origin main
```

The `[skip ci]` is required: any commit pushed to `main` outside a release would
otherwise trigger a `main` build that fails the "must come from a tag" guard.

Expected: prod goes `OutOfSync` (the Application tracks `main`), then a manual
Sync restores the previous digests. Verify `/version` returns `1.0.0` and item 3
returns its old value. To return to the hotfix, revert the revert and sync
again. This is the same mechanism used for any production rollback, and it
leaves an auditable commit rather than an undocumented cluster change.

### 9.7 Common failures in the full simulation

| Symptom | Cause / fix |
|---|---|
| Fix branch build is skipped entirely | branch does not match the job regex; use `fix/...`, then **Scan Multibranch Pipeline Now** |
| `unsupported branch name: 'fix/...'` | Jenkins job predates the regex change; update the job filter in the UI (§9.1) or use `bugfix/...` |
| `main builds must come from a tag` | `main` was pushed without the tag: push `main` and the tag together, or rerun `release.sh` (tag is local) |
| `version 0.0.1-dev.N does not sort above newest existing tag v1.0.0` | the back-merge to `develop` has not happened yet (§5) |
| `git push` from `GitOps` fails with 403 | main/develop protection blocks the bot; allow the credential to bypass (§8) |
| prod stays `OutOfSync` | expected until the manual Sync; verify the App tracks `main` first |
| prod App `Unknown` or `path ... does not exist` | prod tracks `main` before the release merge, or staging tracks a deleted release branch; retarget (§9.1) |
| prod shows the old item value | compare the running image digest with `gitops/overlays/prod/kustomization.yaml`; the pin commit may not have been synced |
| smoke passes but `/version` shows the old version | the Ingress is routing to a pod from the previous ReplicaSet; wait for `rollout status`, then re-check |
