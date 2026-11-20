# Git workflow — developer change to production

One page, four steps, three Jenkins builds and one manual approval. The
example change is real: `POST /ingest` currently accepts a negative claim
amount. The fix rejects it with `422`. Any change follows the same flow.

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

## Step 1 — fix on a branch, merge to develop

```bash
git switch develop
git pull --ff-only
git switch -c fix/negative-claim

# services/ingest/src/ingest/schemas/ingest.py
# reject payload.claim_amount < 0 with a validation error
# services/ingest/tests/test_ingest.py
# add: negative -> 422, positive -> 200, missing -> 200

git commit -am "fix(ingest): reject negative claim amounts"
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
and the monotonicity guard fails the build.

**Expected after the back-merge:** the next `develop` build reports
`version=1.0.1-dev.<M>+<sha>` and deploys dev normally.

## Hotfix (same flow, three commands)

```bash
git fetch --tags
git switch -c hotfix/1.0.1 v1.0.0
# fix, commit, push -> staging build (version 1.0.1-hotfix.<J>+<sha>)
# merge to main -> ./scripts/release.sh patch -> push main+tag -> prod Sync
```

Staging receives the hotfix overlay the same way a release does.

## Rollback

```bash
git switch main
git log --oneline -5          # find chore(gitops): pin 1.0.1 [skip ci]
git revert --no-commit <pin>
git commit -m "revert(gitops): roll back prod to 1.0.0 [skip ci]"
git push origin main
```

Then Sync `bituach-prod` again. The revert must carry `[skip ci]`, otherwise it
triggers an untagged `main` build that fails by design.

## One-time setup (not part of every change)

1. WSL git identity for `release.sh`:
   `git config user.name "Daniel Barel"` and `git config user.email "dbarel@gmail.com"`.
2. Jenkins branch filter accepts `fix/*` (or use `bugfix/*`).
3. Jenkins credential `github-token` exists and can push to `main` and `develop`.
4. `main` branch protection allows the pipeline to push the digest commit.
5. Argo CD prod tracks `main` (the first-release step above).

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| The fix branch never appears in Jenkins | the job filter predates `fix/*`; update it in the UI or use `bugfix/*` |
| `main builds must come from a tag` | `main` was pushed without the tag; push both together |
| `version ... does not sort above newest existing tag` | the back-merge to `develop` is missing (step 5) |
| `GitOps` stage fails with 403 | branch protection blocks the bot on `main` |
| prod App `Unknown` / `path does not exist` | prod tracks `main` before the release merge |
| prod stays `OutOfSync` | expected until the manual Sync |
| prod shows the old version | the pin commit was not synced; check the App's synced revision |
| smoke fails from Jenkins only | `host.docker.internal` / IPv4 resolution; see `SMOKE_RESOLVE_IP` |
