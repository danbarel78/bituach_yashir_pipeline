# Requirements coverage review — versioning, secrets, environment topology

**Date:** 2026-11-19
**Question:** for each of the three design sub-tasks, what did we already cover
before this review, what was missing, and where is it answered now?

**Legend:** ✅ covered · 🟡 partial (some artifact exists, not the whole
obligation) · ❌ missing

## 0. Summary

| Sub-task | Before this review | After | Remaining work |
|---|---|---|---|
| Version management (GitFlow, SemVer, tagging, changelog, rollout) | 🟡 mostly implemented, scattered across `handoff.md`, `docs/git-workflow.md`, `ci/scripts/version.py`; changelog artifact missing; rollout alternatives in one sentence | ✅ `docs/versioning.md` + `CHANGELOG.md` | cut `v1.0.0`; automate tag retention |
| Secrets management (Vault + ESO, CI + runtime, no exposure) | 🟡 Vault and ESO installed; CI credential real; **no runtime wiring at all**; no `docs/secrets.md` | 🟡 `docs/secrets.md` specifies the full path, including manifests and verification | P5: create `ClusterSecretStore` + `ExternalSecret`, wire `secretKeyRef`, add gitleaks |
| Environment topology (dev/staging/prod, justification, Terraform) | 🟡 Terraform complete and applied; justification only two short paragraphs; no topology doc | ✅ `docs/environment-topology.md` | scope Argo CD RBAC; prod cluster is documented evolution |

The important distinction: **version management and the Terraform topology were
already built, and were only under-documented.** Secrets is the opposite —
well documented as an intention, but the runtime path does not exist yet.
This review does not pretend otherwise.

## 1. Sub-task 1 — Version management

| Required item | Existing artifact before review | Status | Where it is answered now |
|---|---|---|---|
| Branching strategy (GitFlow) | `docs/git-workflow.md` §1–2; real branch/merge history; `version.py` rejects unknown branches | ✅ | `docs/versioning.md` §2 |
| Semantic Versioning conventions | `handoff.md` §6; `ci/scripts/version.py` docstring; `ci/tests/test_version.py`; `base_version.json` | ✅ but fragmented | `docs/versioning.md` §3 |
| Container image tagging policy (immutable vs `latest`) | `handoff.md` §2 and §6; `docs/git-workflow.md` §2; digest-pinned overlays; Jenkins `Preflight` guard | ✅ | `docs/versioning.md` §4 |
| Changelog management | `scripts/release.sh` generates Keep-a-Changelog sections from Conventional Commits; **no `CHANGELOG.md` existed** | 🟡 → ✅ | `docs/versioning.md` §5; new `CHANGELOG.md` baseline |
| Kubernetes rollout strategy | `RollingUpdate` with `maxSurge: 1` / `maxUnavailable: 0` in all three Deployments; `handoff.md` §6; review doc concept 6; blue-green/canary mentioned in one sentence | 🟡 → ✅ | `docs/versioning.md` §6 (comparison + decision + migration path) |

### What was genuinely missing

1. **No `CHANGELOG.md`.** The generator existed, but a reviewer opening the repo
   saw no changelog. Fixed with a baseline file.
2. **No consolidated versioning document.** The policy was spread over four
   files and two of them (`handoff.md`, review doc) are project-management
   documents, not deliverable docs. Fixed.
3. **Rollout alternatives were not evaluated.** The task asks to define the
   strategy, not only to set `maxSurge`. `docs/versioning.md` §6 now compares
   Rolling Update, blue-green and canary on blast radius, cost, rollback,
   complexity and metric requirements, and justifies the choice.
4. **Tag retention** is policy only. No Jenkins stage prunes old tags, so the
   "keep last 3" statement in `handoff.md` is not enforced. Documented as a gap.

### Already strong, no action needed

- `version.py` is real code with unit tests, not a description.
- The overlays pin digests, so the "immutable" claim is verifiable, not a
  promise.
- The `Preflight` guard actually fails a build that reintroduces `latest`.

## 2. Sub-task 2 — Secrets management (Vault + ESO)

| Required item | Existing artifact before review | Status | Where it is answered now |
|---|---|---|---|
| Vault as the secret source | `platform/values/vault.yaml`, installed by `scripts/bootstrap.sh`, verified by `scripts/verify.sh` | ✅ installed | `docs/secrets.md` §3–4 |
| External Secrets Operator | `platform/values/external-secrets.yaml`, 3 deployments ready, both CRDs present | ✅ installed | `docs/secrets.md` §1, §4 |
| `ClusterSecretStore` / `SecretStore` | **none** | ❌ | specified in `docs/secrets.md` §4.3 |
| `ExternalSecret` per service/environment | **none** | ❌ | specified in `docs/secrets.md` §4.4 |
| Secure injection into Pods | Deployments consume only the `bituach-env` ConfigMap; **no `secretKeyRef`** | ❌ | specified in `docs/secrets.md` §4.5 |
| No secrets in manifests or source code | True by absence today; no secret material is committed except the dev-mode Vault token `root` | 🟡 | `docs/secrets.md` §6, §4.1 (explicit exception) |
| No secrets in logs | JSON logger never logs bodies/headers; **validation errors log `exc.errors()`**, which can include input | 🟡 | `docs/secrets.md` §7 (caveat + fix) |
| CI/CD-time secrets | Jenkins credential `github-token`; `withCredentials`; `--password-stdin`; `set +x`; credential ID only in the Jenkinsfile | ✅ implemented | `docs/secrets.md` §5 |
| Rotation | Described in `handoff.md` §8 only; env-var injection needs a restart | 🟡 | `docs/secrets.md` §4.6 (file mount vs env var vs reloader) |
| `handoff.md` claim of a gitleaks stage | **not in `ci/Jenkinsfile` or `ci/scripts/scan.sh`** | ❌ | listed as a gap in `docs/secrets.md` §5.2 |
| `handoff.md` claim of a rotation demo | **not implemented** (no `ExternalSecret` to rotate) | ❌ | status table in `docs/secrets.md` §1 |

### The honest headline

Vault and ESO are installed, healthy and proven reachable. The **path between
them and a pod does not exist**. A reviewer who runs
`kubectl get externalsecret -A` today gets "no resources found". That is P5,
and `docs/secrets.md` is now its specification rather than a claim of
completion.

### Two inaccuracies found in existing documents

1. `handoff.md` §2 says the Vault dev token is "not committed anywhere". It is
   in `platform/values/vault.yaml` as `devRootToken: "root"`. That is defensible
   for in-memory dev mode, but the statement is wrong.
2. `handoff.md` §3/§8 lists gitleaks and a rotation demo as implemented. Neither
   exists. `docs/review-and-walkthrough.md` already corrects the status for
   P5; the new secrets doc carries the same correction in one place.

## 3. Sub-task 3 — Environment topology

| Required item | Existing artifact before review | Status | Where it is answered now |
|---|---|---|---|
| Dev/Staging/Prod design | `terraform/envs/{dev,staging,prod}`, `gitops/overlays/*`, applied and synced | ✅ | `docs/environment-topology.md` §1, §3 |
| Namespaces vs separate clusters, justified | Two paragraphs in `handoff.md` §4 and one Q&A in the review doc | 🟡 → ✅ | `docs/environment-topology.md` §2 |
| Terraform IaC example | 5 modules + 3 environments, `terraform validate` clean, applied | ✅ | `docs/environment-topology.md` §4 (annotated excerpts) |
| ResourceQuotas | `terraform/modules/resources` (quota + LimitRange) | ✅ | §4.3, §4.4 sizing check |
| Requests/Limits | module defaults + overlay patches per environment | ✅ | §3, §5 |
| RBAC | dev `edit`; staging `view` + CI `edit`; prod `view` | ✅ | §3, §4.2 |
| Service Accounts | `bituach-app`, no token, no role rules | ✅ | §4.3 |
| NetworkPolicies | default-deny + ingress + intra-namespace + DNS; prod no internet egress | ✅ | §4.3 |
| HPA / autoscaling | HPA v2, 2–3 @ 70% CPU in staging/prod; metrics-server installed | ✅ | §4.3, §4.4 |
| Replica counts | overlays: 1 / 2 / 2 | ✅ | §3, §5 (and why not Terraform) |

### What was genuinely missing

1. **No `docs/environment-topology.md`.** Terraform comments in
   `envs/*/main.tf` and `modules/*/versions.tf` already pointed at this file;
   the references were dangling. Fixed.
2. **No written justification.** "Namespaces for the POC, clusters for prod"
   existed as a conclusion, not an argument. The new doc compares nine criteria
   and states explicitly what a namespace does *not* isolate.
3. **No sizing analysis.** The quota values were plausible but unexamined. The
   new §4.4 shows the steady-state arithmetic and one real consequence: in
   staging the 4-CPU quota binds before three services can all reach HPA max 3
   (nine pods × 500m = 4.5 CPU). That is a documented trade-off and an
   actionable recommendation, not a hidden surprise.
4. **The Terraform/GitOps boundary was asserted, not explained.** The new §6
   gives the failure mode each boundary prevents (Terraform fighting the HPA;
   an app commit raising its own quota).

### Coverage that was already good

The Terraform is the strongest artifact of the three sub-tasks: five
single-concern modules, three environment compositions, all applied to the
cluster, quoted in the doc with the real values. Nothing needed to be written
for it to satisfy the assignment; it needed to be explained.

## 4. Existing documents — what each one actually covers

| File | Covers | Does **not** cover |
|---|---|---|
| `handoff.md` | Scope, locked decisions, phase plan, milestone log, environment as observed | It is a project record; §3 describes the target state as if complete |
| `docs/git-workflow.md` | GitFlow commands, branch→version→environment, Jenkins usage, release steps, rollback | Rollout strategy; tagging policy rationale; changelog format |
| `docs/review-and-walkthrough.md` | Plain-language status, requirement matrix, demos, Q&A, runbook-style commands | Written as of P3; versioning/secrets/topology deep dives absent |
| `platform/README.md` | Installed platform components, versions, endpoints | Secret flow; topology; quotas |
| `terraform/modules/README.md` | Module responsibilities and the Terraform/GitOps boundary | Environment values and justification |
| `ci/scripts/version.py` (docstring) | The authoritative branch→version table | Image tagging policy; changelog; rollout |
| `docs/standards/backend-standards.md` | Python/FastAPI engineering standard | Any infrastructure topic |
| `README.md` | **does not exist** | Required deliverable: how to run and test |

## 5. Documents created by this review

| File | Answers |
|---|---|
| `docs/versioning.md` | Sub-task 1 in full: GitFlow, SemVer, immutable tags/digests, changelog, rollout comparison and decision |
| `docs/secrets.md` | Sub-task 2 in full: threat model, Vault/ESO architecture, target manifests, CI-time vs runtime, log hygiene, rotation, hardening, acceptance test |
| `docs/environment-topology.md` | Sub-task 3 in full: topology, namespace-vs-cluster decision, environment matrix, Terraform walkthrough, sizing, boundary, limitations |
| `docs/requirements-coverage.md` | This review |
| `CHANGELOG.md` | Changelog management artifact (baseline; `release.sh` prepends releases above it) |

Code comments in `ci/scripts/version.py`, `platform/values/*.yaml` and
`terraform/**` referenced `docs/versioning.md`, `docs/secrets.md` and
`docs/environment-topology.md` before those files existed. Those references now
resolve.

## 6. Documentation drift found (not fixed, because it is history)

`handoff.md` §3 describes the **target end state** and reads like a status
report. These specific claims are ahead of the code:

| Claim | Reality |
|---|---|
| §2: Vault dev token "not committed anywhere" | `platform/values/vault.yaml` contains `devRootToken: "root"` |
| §3/§8: gitleaks stage fails on committed secrets | No gitleaks stage exists |
| §3/§8: rotation demo | No `ExternalSecret` exists to rotate |
| §6: rollout has a "progress deadline" | No `progressDeadlineSeconds` is set in any Deployment |
| §10: retention stage keeps the last 3 tags | No such stage in `ci/Jenkinsfile` |
| §11: Argo CD values in `platform/argocd/values.yaml` | Actual path is `platform/values/argocd.yaml` |
| §11: image promotion commit records version, digest **and pipeline URL** | `ci/scripts/gitops-update.sh` commits only `chore(gitops): pin <version> [skip ci]`; the digest is in the diff, the pipeline URL is not recorded |
| §13: services contain `requirements.txt` | They use `pyproject.toml` + `uv.lock` |
| §13: `ci/scripts/release.sh` | Actual path is `scripts/release.sh` |

`docs/review-and-walkthrough.md` already warns that `handoff.md` §3 is a target
state. The milestone log in `handoff.md` §18 is the reliable status source.

## 7. Remaining gaps, in priority order

1. **P5 — runtime secrets.** Apply the `ClusterSecretStore`, the three
   `ExternalSecret` objects per environment and the `secretKeyRef` wiring
   specified in `docs/secrets.md`; then run the §9 acceptance sequence.
2. **Secret scanning.** Add `gitleaks` to the `Preflight` stage — the pipeline
   currently proves nothing about committed secrets.
3. **Cut `v1.0.0`.** `base_version.json` is still `0.0.0` with no tag, so the
   changelog and the prod promotion path are untested end-to-end.
4. **README.md and `docs/decisions.md`.** Both are explicit deliverables and
   both are absent.
5. **Tag retention stage.** Policy exists; enforcement does not.
6. **Validation-error logging.** Log `loc`/`type`, not `input`, before any
   payload that could contain PII is accepted.
7. **Observability docs.** `docs/observability-design.md` and
   `docs/runbook.md` are referenced by `handoff.md` and still missing; outside
   the three sub-tasks reviewed here.
