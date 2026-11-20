# Git workflow — developer change to production

Four steps to production, one housekeeping step, three promotion builds (dev,
staging, prod) and one manual approval. The fix branch itself also gets a gate
build; it pushes nothing. The example change is real: `POST /ingest` currently
accepts a negative claim amount. The fix rejects it with `422`. Any change
follows the same flow.

## The map

```
fix/negative-claim ──PR──► develop ──cut──► release/1.0.0 ──merge──► main ──tag v1.0.0
                            │ dev build        │ staging build         │ prod build
                            └ smoke 9/9        └ smoke 9/9            └ manual Sync
```

| Environment | Argo CD tracks | Which build updates its overlay |
|---|---|---|
| dev | `develop` | every `develop` build |
| staging | `develop` | only `release/*` and `hotfix/*` builds |
| prod | `main` | the tagged `main` build, then a manual Sync |

Staging and dev share the `develop` branch but not the same directory:
a `develop` build touches only `gitops/overlays/dev`; a release build touches
only `gitops/overlays/staging`.

Jenkins scans the repository every 5 minutes. Use **Scan Multibranch Pipeline
Now** if you do not want to wait for the next scan.

## Version and tag rules

The developer never edits a version. `scripts/release.sh` is the only bump.

| Stage | Version | Container tag | Git tag |
|---|---|---|---|
| fix branch | `0.0.1-negative-claim.<N>+<sha>` | not pushed | — |
| develop | `0.0.1-dev.<M>+<sha>` | `0.0.1-dev.<M>-<sha>` | — |
| release/1.0.0 | `1.0.0-rc.<K>+<sha>` | `1.0.0-rc.<K>-<sha>` | — |
| main | `1.0.0` | `1.0.0` | `v1.0.0` |

`<N>`, `<M>`, `<K>` are Jenkins build numbers. The Git tag keeps the `v`; the
container tag does not. The overlay pins the image **digest**, not the tag.

The table shows the **first release**. Once `v1.0.0` exists, the next cycle
produces `1.0.1-negative-claim.<N>` (or `1.1.0-...` for a feature),
`1.0.1-dev.<M>`, `1.0.1-rc.<K>`, and finally `1.0.1` / `v1.0.1`. The shape of
every step is identical; only the numbers move.

## Step 1 — fix on a branch, merge to develop

```bash
git switch develop
git pull --ff-only
git switch -c fix/negative-claim

# services/ingest/src/ingest/schemas/ingest.py
# reject payload.claim_amount < 0 with a validation error
# services/ingest/tests/test_ingest.py
# add: negative -> 422, positive -> 200, missing -> 200

git add services/ingest/src/ingest/schemas/ingest.py services/ingest/tests/test_ingest.py
git commit -m "fix(ingest): reject negative claim amounts"
git push -u origin fix/negative-claim
```

Open a pull request into `develop` and merge it after the branch build is green.
That PR is the code-review gate.

**Expected in Jenkins — fix branch**

| Item | Value |
|---|---|
| Build result | `SUCCESS` |
| Version line | `version=0.0.1-negative-claim.<N>+<sha> ... target=none` |
| `Push` / `GitOps` / `Smoke` | skipped (nothing deployed) |
| Images | none pushed |

**Expected in Jenkins — develop build after the merge**

| Item | Value |
|---|---|
| Version line | `version=0.0.1-dev.<M>+<sha> ... target=dev` |
| `Push` | three images `0.0.1-dev.<M>-<sha>` |
| `GitOps` | `chore(gitops): pin 0.0.1-dev.<M>+<sha> [skip ci]` on `develop` |
| `Smoke` | `All 9 smoke checks passed.` |

**Expected behaviour in dev**

```powershell
curl.exe -sk --resolve engine.dev.bituach.localhost:443:127.0.0.1 https://engine.dev.bituach.localhost/version
# {"service":"engine","version":"0.0.1-dev.<M>+<sha>","environment":"dev"}

curl.exe -sk --resolve ingest.dev.bituach.localhost:443:127.0.0.1 `
  -X POST https://ingest.dev.bituach.localhost/ingest `
  -H "Content-Type: application/json" `
  -d '{\"source\":\"demo\",\"payload\":{\"claim_amount\":-100}}'
# HTTP 422 {"error":"validation_error",...}

# positive control
# claim_amount: 100 -> HTTP 200 {"accepted":true,...}
```

## Step 2 — cut the release branch (staging)

```bash
git switch develop
git pull --ff-only
git switch -c release/1.0.0
git push -u origin release/1.0.0
```

Nothing else to click. The release build writes the staging overlay to
`develop`, and the staging Application (which tracks `develop`) reconciles it.

> `develop` often ends with a `chore(gitops): pin … [skip ci]` commit. The
> release branch may be cut from that commit; the pipeline still builds it,
> because `[skip ci]` only suppresses builds on `develop` and `main`.

**Expected in Jenkins — release build**

| Item | Value |
|---|---|
| Version line | `version=1.0.0-rc.<K>+<sha> ... target=staging` |
| `Push` | three images `1.0.0-rc.<K>-<sha>` |
| `GitOps` | a `[skip ci]` commit on `develop` changing `gitops/overlays/staging` only |
| `Wait for Argo CD` | `bituach-staging` `Synced/Healthy` at the pushed revision |
| `Smoke` | `All 9 smoke checks passed.` |

**Expected behaviour in staging**

```powershell
curl.exe -sk --resolve engine.staging.bituach.localhost:443:127.0.0.1 https://engine.staging.bituach.localhost/version
# {"service":"engine","version":"1.0.0-rc.<K>+<sha>","environment":"staging"}

# same negative-claim request against ingest.staging.bituach.localhost
# -> HTTP 422
```

## Step 3 — merge to main, tag, build production

```bash
git switch main
git pull --ff-only
git merge --no-ff release/1.0.0
./scripts/release.sh major        # first release: 0.0.0 -> 1.0.0
git push origin main --follow-tags
```

`release.sh` bumps `base_version.json`, regenerates `CHANGELOG.md`, commits, and
creates the annotated `v1.0.0` tag. `main` and the tag must be pushed together:
the `main` branch build is the release build; tags alone do not trigger a build.

> If `main` is protected against direct pushes, merge `release/1.0.0` into
> `main` through a pull request, then run `release.sh` and push the tag from
> your local `main`. The rest of the flow is identical; the production approval
> is still the Argo CD **Sync**.

The bump argument must match the release branch: first release `major`
(`0.0.0 → 1.0.0`), a minor release `minor` (`1.0.0 → 1.1.0`), a patch `patch`
(`1.0.0 → 1.0.1`).

**Expected from `release.sh`**

```text
==> bumped base_version.json to v1.0.0
==> regenerated CHANGELOG.md
[main <sha>] chore(release): v1.0.0
==> Release v1.0.0 created locally...
```

Verify before pushing: `git describe --exact-match --tags HEAD` → `v1.0.0`.

**Expected in Jenkins — main build**

| Item | Value |
|---|---|
| Version line | `version=1.0.0 tag=1.0.0 branch=main ... target=prod` |
| `Push` | three images tagged `1.0.0` |
| `GitOps` | `chore(gitops): pin 1.0.0 [skip ci]` on `main` |
| `Wait` / `Smoke` | skipped for prod by design |
| `Prod handoff` | `Argo CD will show bituach-prod as OutOfSync; prod deploys only after a manual Sync.` |

Verify that the build wrote the production pin to `main`:

```bash
git fetch origin main
git log --oneline -2 origin/main
# 333ceff chore(gitops): pin 1.0.0 [skip ci]
# e3d12b8 chore(release): v1.0.0
```

### First release only — point prod at main

`main` had no prod overlay before this merge. Once the main build has pushed the
pin, make the one-time switch (a Git commit, not `kubectl patch`, because the
root Application self-heals these manifests):

```bash
git switch develop
# gitops/argocd/apps/prod.yaml: targetRevision: main   (was develop)
git add gitops/argocd/apps/prod.yaml
git commit -m "chore(argocd): track main in prod [skip ci]"
git push origin develop
```

```powershell
kubectl -n argocd annotate application bituach-root argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get application bituach-prod
# NAME           SYNC STATUS   HEALTH STATUS
# bituach-prod   OutOfSync     Healthy
```

Later releases need no retargeting.

## Step 4 — approve and verify production

Argo CD → `bituach-prod` → **Sync**. This is the production approval gate.

CLI alternative (PowerShell; the patch file avoids quoting problems):

```powershell
Set-Content -Path "$env:TEMP\argo-sync.json" -Value '{"operation":{"sync":{"prune":false}}}' -Encoding ascii
kubectl -n argocd patch application bituach-prod --type merge --patch-file "$env:TEMP\argo-sync.json"
```

```powershell
kubectl -n argocd get application bituach-prod
# Synced / Healthy

kubectl -n bituach-prod get deploy,pods
# 6 pods Ready (2 per service)

curl.exe -sk --resolve engine.bituach.localhost:443:127.0.0.1 https://engine.bituach.localhost/version
# {"service":"engine","version":"1.0.0","environment":"prod"}

curl.exe -sk --resolve ingest.bituach.localhost:443:127.0.0.1 `
  -X POST https://ingest.bituach.localhost/ingest `
  -H "Content-Type: application/json" `
  -d '{\"source\":\"demo\",\"payload\":{\"claim_amount\":-100}}'
# HTTP 422
```

Positive control: `claim_amount: 100` → `HTTP 200`, `"accepted":true`.

## Step 5 — housekeeping (required)

```bash
git switch develop
git merge --no-ff main
git push origin develop
git push origin --delete release/1.0.0
```

The back-merge brings `base_version.json` = 1.0.0 to `develop`. Without it the
next develop build computes `0.0.1-dev.N`, which does not sort above `v1.0.0`,
and the monotonicity guard fails the build. If the merge conflicts, keep
`develop`'s overlay files (they point at the newest dev/staging images) and take
`main`'s `base_version.json` and `CHANGELOG.md`.

**Expected after the back-merge:** the next `develop` build reports
`version=1.0.1-dev.<M>+<sha>` and deploys dev normally.

## Hotfix (same flow, three steps)

```bash
git fetch --tags
git switch -c hotfix/1.0.1 v1.0.0
# smallest possible fix + test
git add -A
git commit -m "fix(ingest): reject a negative claim source"
git push -u origin hotfix/1.0.1
```

**Expected in Jenkins — hotfix build**

| Item | Value |
|---|---|
| Version line | `version=1.0.1-hotfix.<J>+<sha> ... target=staging` |
| `Push` / `GitOps` | hotfix images; staging overlay pinned on `develop` |
| `Smoke` | `All 9 smoke checks passed.` |
| staging `/version` | `1.0.1-hotfix.<J>+<sha>` |

Then release it exactly like a normal release, with `patch`:

```bash
git switch main && git pull --ff-only
git merge --no-ff hotfix/1.0.1
./scripts/release.sh patch        # 1.0.0 -> 1.0.1
git push origin main --follow-tags
```

Expected: `v1.0.1` tag; `main` build `version=1.0.1 ... target=prod`; image
`1.0.1`; prod `OutOfSync`; after Sync, prod `/version` is `1.0.1`.

Finish with the same housekeeping as a normal release:

```bash
git switch develop && git pull --ff-only
git merge --no-ff main && git push origin develop
git push origin --delete hotfix/1.0.1
```

Staging receives the hotfix overlay the same way a release does; no retargeting.

## Rollback

```bash
git switch main
git log --oneline -5 -- gitops/overlays/prod   # find the pin to undo
git revert --no-commit <pin>
git commit -m "revert(gitops): roll back prod to 1.0.0 [skip ci]"
git push origin main
```

Then Sync `bituach-prod` again. Expected: the App goes `OutOfSync`, Sync returns
it to `Synced/Healthy`, and `/version` returns the previous release (for example
`1.0.0`). The revert must carry `[skip ci]`, otherwise it triggers an untagged
`main` build that fails by design.

## One-time setup (check before the first run)

| Check | Command | Expected |
|---|---|---|
| Cluster | `kubectl get nodes` | `desktop-control-plane   Ready` |
| Platform | `./scripts/verify.sh` (WSL) | `21/21 checks passed` |
| Argo apps | `kubectl -n argocd get applications` | four `Synced/Healthy` |
| WSL identity | `wsl -d Ubuntu -- bash -lc 'git config user.email'` | non-empty (needed by `release.sh`) |
| Jenkins filter | `curl.exe -u admin:admin -s -o "$env:TEMP\job.xml" http://localhost:8080/job/bituach-yashir/config.xml; Select-String "$env:TEMP\job.xml" "regex"` | contains `fix/.+` or use `bugfix/*` |
| Credential | `curl.exe -u admin:admin -s "http://localhost:8080/credentials/store/system/domain/_/api/json?tree=credentials[id]"` | `github-token` |
| Main write path | GitHub → Settings → Branches → `main` | the pipeline identity can push the pin commit |
| Prod tracking | `kubectl -n argocd get application bituach-prod -o jsonpath='{.spec.source.targetRevision}'` | `main` after the first release; `develop` before it |

If `main` is protected, allow the `github-token` identity to bypass the PR rule
(or temporarily allow direct pushes for the simulation). Without that, the
`GitOps` stage fails with 403 after the images are pushed.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| The fix branch never appears in Jenkins | the job filter predates `fix/*`; update it in the UI or use `bugfix/*` |
| Release build is `NOT_BUILT` with `skipped: [skip ci]` | the branch was cut from a pin commit with the old pipeline; merge `develop` into it so it gets the current Jenkinsfile |
| Two builds run for the same revision | old dual trigger (folder scan + per-branch poll); current pipeline scans from the folder only — merge `develop` into the branch and rebuild |
| `main builds must come from a tag` | `main` was pushed without the tag; push both together |
| `version ... does not sort above newest existing tag` | the back-merge to `develop` is missing (step 5) |
| `GitOps` stage fails with 403 | branch protection blocks the bot on `main` |
| prod App `Unknown` / `path does not exist` | prod tracks `main` before the release merge |
| prod stays `OutOfSync` | expected until the manual Sync |
| prod shows the old version | the pin commit was not synced; check the App's synced revision |
| smoke fails from Jenkins only | `host.docker.internal` / IPv4 resolution; see `SMOKE_RESOLVE_IP` |
