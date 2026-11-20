# Secrets management — Vault → External Secrets Operator → Pods

This document answers the secrets part of the assignment: how secrets are
sourced, injected at **runtime**, injected at **CI/CD time**, and kept out of
manifests, source code and logs.

It is deliberately split into **what runs today** and **the wiring that is
designed but not yet applied**. The distinction matters: Vault and the External
Secrets Operator (ESO) are installed and verified, but no `ClusterSecretStore`,
`ExternalSecret` or `secretKeyRef` exists in the repository yet. P5 is the
remaining implementation step; this document is its specification.

## 1. Status

| Capability | Status | Evidence / gap |
|---|---|---|
| Vault deployed (dev mode, in-memory, auto-unsealed) | ✅ installed | `platform/values/vault.yaml`, `scripts/bootstrap.sh`, `scripts/verify.sh` |
| Vault UI reachable over TLS | ✅ verified | `https://vault.localhost` |
| External Secrets Operator deployed | ✅ installed | `platform/values/external-secrets.yaml`; 3 deployments ready |
| ESO CRDs present | ✅ verified | `externalsecrets.external-secrets.io`, `clustersecretstores.external-secrets.io` |
| Vault Kubernetes auth configured | ❌ not yet | dev mode enables only the token method; `auth/kubernetes` is not mounted |
| `ClusterSecretStore` / `SecretStore` | ❌ not yet | no manifest in `gitops/` |
| `ExternalSecret` per service/environment | ❌ not yet | no manifest in `gitops/` |
| Secret consumed by a Pod | ❌ not yet | Deployments use a ConfigMap only (`envFrom: configMapRef: bituach-env`) |
| CI/CD registry credential outside Git | ✅ implemented | Jenkins `github-token`, `withCredentials`, `docker login --password-stdin` |
| Secret scanning of commits | ❌ not yet | a `gitleaks` stage is planned; `ci/scripts/scan.sh` covers SAST, deps, image only |
| Secrets absent from logs | ⚠️ by design, with one caveat | JSON logger never logs bodies/headers; validation errors log `exc.errors()` (see §8) |

## 2. Goals and threat model

**Must hold:**

1. No secret value is ever committed to Git, written into a Kubernetes manifest,
   baked into an image layer, or printed to a CI console.
2. A pod can read only the secrets of its own service in its own environment.
3. Rotating a value does not require a code change, a rebuild or a manifest edit.
4. Every read is attributable (Vault audit log in production).

**Out of scope for the POC:** a compromised cluster-admin, node-level memory
scraping, and hardware-backed key management. Those are stated as limitations,
not solved by adding another YAML file.

## 3. Architecture

Two independent planes, because CI credentials and runtime credentials have
different lifetimes and different consumers.

```
RUNTIME PLANE

  ┌──────────────┐   Kubernetes auth    ┌─────────────────────┐
  │ Vault        │◄─────────────────────│ External Secrets    │
  │ secret/<env>/│                      │ Operator (ESO)      │
  │ <service>    │─── read KV v2 ──────►│                     │
  └──────────────┘                      └──────────┬──────────┘
                                                   │ creates/updates
                                                   ▼
                                        ┌─────────────────────┐
                                        │ Secret <svc>-secrets│  (namespace-scoped)
                                        └──────────┬──────────┘
                                                   │ secretKeyRef / volume
                                                   ▼
                                        ┌─────────────────────┐
                                        │ Pod (app container) │
                                        └─────────────────────┘

CI/CD PLANE

  GitHub PAT ──► Jenkins credential store ──► withCredentials ──► docker login / git push
                 (encrypted, never in Git)      (masked in logs)
```

Why ESO rather than the Vault Agent Injector: ESO produces a normal Kubernetes
`Secret`, so the application has no Vault SDK, no sidecar and no Vault address.
The workload stays portable and the only Vault-aware component is ESO. The
Vault injector is disabled in `platform/values/vault.yaml` for exactly this
reason.

## 4. Runtime secret path

### 4.1 Vault layout

KV v2, one path per environment and service:

```
secret/
  dev/
    engine      { "app_secret_token": "…", "downstream_api_key": "…" }
    data        { "app_secret_token": "…" }
    ingest      { "app_secret_token": "…" }
  staging/
    engine      …
  prod/
    engine      …
```

- The path encodes the environment, so a prod pod cannot read a staging value
  even if its policy is wrong in the other direction.
- Values are written with `vault kv put`, never with `kubectl create secret` and
  never in Git.
- The dev-mode root token is `root` and is present in
  `platform/values/vault.yaml`. That is an explicit, documented exception: dev
  mode is in-memory and localhost-only, so the token has no confidentiality. It
  **must not** be copied to staging/prod, where Kubernetes auth with short-lived
  tokens replaces it. This is the one place a credential-shaped string exists in
  the repository, and it is labelled as such.

### 4.2 Vault Kubernetes auth (target state)

```bash
# Run once against the in-cluster Vault (vault CLI is used through kubectl exec).
kubectl -n vault exec -it vault-0 -- vault auth enable kubernetes

kubectl -n vault exec -it vault-0 -- vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc"

kubectl -n vault exec -it vault-0 -- vault policy write eso-bituach - <<'EOF'
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}
EOF

kubectl -n vault exec -it vault-0 -- vault write auth/kubernetes/role/eso-bituach \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-bituach \
  ttl=1h
```

The role is bound to ESO's service account, not to the application's. The
application never authenticates to Vault; ESO does it on the application's
behalf, which is what allows the Secret to be a plain Kubernetes object.

Production refinement: one role per environment with a path policy restricted
to `secret/data/prod/*`, and a namespaced `SecretStore` in each application
namespace instead of one cluster-wide store.

### 4.3 `ClusterSecretStore` (target state)

> API version note: the manifests below use `external-secrets.io/v1beta1`.
> Check which versions the installed CRD serves before applying
> (`kubectl get crd clustersecretstores.external-secrets.io -o jsonpath='{.spec.versions[*].name}'`)
> and use the newest served version if it has dropped `v1beta1`.

```yaml
# gitops/infra/eso/cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-bituach
spec:
  provider:
    vault:
      server: http://vault.vault.svc.cluster.local:8200
      path: secret          # KV v2 mount
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: eso-bituach
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

The store contains no credential. It says *where Vault is* and *which identity
ESO uses*. That is the whole point: a manifest can be fully public and still
produce a secret.

### 4.4 `ExternalSecret` per service and environment (target state)

One object per service, placed in the environment overlay so its namespace is
the environment:

```yaml
# gitops/overlays/prod/external-secrets.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: engine-secrets
  namespace: bituach-prod
spec:
  refreshInterval: 60s
  secretStoreRef:
    name: vault-bituach
    kind: ClusterSecretStore
  target:
    name: engine-secrets
    creationPolicy: Owner      # delete the Secret when this object is deleted
  data:
    - secretKey: APP_SECRET_TOKEN
      remoteRef:
        key: prod/engine       # relative to the store's mount path
        property: app_secret_token
    - secretKey: DOWNSTREAM_API_KEY
      remoteRef:
        key: prod/engine
        property: downstream_api_key
```

`ExternalSecret` names keys, not values. Copying the same object into
`staging` changes only `namespace` and the Vault path (`key: staging/engine`),
so promotion remains a reviewable diff with no secret material in it.

### 4.5 Consuming the Secret in the Pod (target state)

Explicit `secretKeyRef` per variable is preferred over `envFrom.secretRef`:

```yaml
          env:
            - name: SERVICE_NAME
              value: engine
            - name: APP_SECRET_TOKEN
              valueFrom:
                secretKeyRef:
                  name: engine-secrets
                  key: APP_SECRET_TOKEN
                  optional: false     # a missing secret must fail the pod, not start half-configured
```

- `optional: false` turns a failed sync into a visible `CreateContainerConfigError`
  instead of a silently degraded service.
- `secretKeyRef` selects exactly the keys the process needs; `envFrom` would
  import every key in the Secret and make an accidental extra secret available
  to the app.
- The Deployment itself contains only the **name** of the Secret. `kubectl get
  deploy -o yaml` is safe to paste into a ticket.
- For a private registry, the same mechanism creates the pull secret:
  an `ExternalSecret` targeting `type: kubernetes.io/dockerconfigjson`, referenced
  by `serviceAccount.imagePullSecrets`. Public GHCR packages make this
  unnecessary in the POC.

### 4.6 Rotation

```
vault kv put secret/prod/engine app_secret_token=<new>
        │
        ▼ (ESO refreshInterval: 60s)
Kubernetes Secret updated
        │
        ├── mounted as a file  → kubelet updates the file (seconds), application must re-read it
        └── injected as an env var → requires a new container process
```

Kubernetes does **not** restart a pod when an env-var-sourced Secret changes.
The runbook therefore has two supported paths:

1. **Recommended:** run a reloader (e.g. stakater/Reloader) that watches the
   Secret and triggers a rolling restart. Because the Deployment already uses
   `maxUnavailable: 0`, the restart is zero-downtime.
2. **Manual:** `kubectl rollout restart deploy/<service>` after verifying that
   ESO's `ExternalSecret` reports `SecretSynced=True`.

A file mount avoids the restart but pushes the re-read responsibility into the
application; the POC uses environment variables because that matches the FastAPI
settings model.

### 4.7 Verification (no value printed)

```bash
# ESO says it synced, without revealing content
kubectl -n bituach-prod get externalsecret engine-secrets \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'

# The Secret exists and has the expected number of keys
kubectl -n bituach-prod get secret engine-secrets \
  -o jsonpath='{.data}' | tr ',' '\n' | wc -l

# The process can see the variable is present, never its value
kubectl -n bituach-prod exec deploy/engine -- \
  sh -c 'test -n "$APP_SECRET_TOKEN" && echo present'
```

The application-side proof is a `GET /config` endpoint that returns
`{"app_secret_token_configured": true}` and never the value. That endpoint is
part of the P5 wiring, not of the current services.

## 5. CI/CD-time secrets

Runtime secrets and pipeline credentials are separate problems. A pipeline needs
a registry token and a Git write token; neither should ever reach a pod.

### 5.1 What is implemented

| Secret | Where it lives | How it is used |
|---|---|---|
| GHCR username/password (classic PAT: `repo`, `write:packages`) | Jenkins credential `github-token`, encrypted at rest | `withCredentials([usernamePassword(...)])` |
| Docker registry session | Process memory only | `echo "$GHCR_TOKEN" \| docker login ghcr.io -u "$GHCR_USER" --password-stdin`, then `docker logout` |
| Git push credential | Same Jenkins credential, injected as `GIT_TOKEN` | consumed by `ci/scripts/gitops-update.sh`; never echoed |
| Kubernetes API access from Jenkins | Generated kubeconfig in `%TEMP%`, created by `ci/jenkins.ps1 up` | never committed; path passed to the container |
| Vault dev root token | `platform/values/vault.yaml` (`root`) | local POC only; labelled as a dev-mode placeholder |

Controls that make this safe in logs:

- `withCredentials` masks the value in the Jenkins console; `set +x` is set
  around the login and push blocks so the shell does not echo the command with
  the token expanded.
- The token is passed with `--password-stdin`, never as `--password`.
- The GitOps commit contains image digests, not credentials. The digest is in the
  diff and the commit message carries the version (`chore(gitops): pin <version>
  [skip ci]`); the Jenkins build that produced it is linked from the build log.
- The Jenkinsfile has no credential literal. The credential ID is the only
  reference.

### 5.2 What is designed, not implemented

| Improvement | Why | How |
|---|---|---|
| Vault-backed CI secrets | A long-lived classic PAT is the biggest remaining credential risk | Jenkins authenticates to Vault with JWT/OIDC (`auth/jwt`), receives a short-lived token, reads the registry credential from `secret/ci/registry` |
| Short-lived registry token | GHCR PATs can outlive their usefulness | GitHub App installation token or a fine-grained token limited to this repository, still stored in Jenkins/Vault |
| `gitleaks` / secret scanning stage | Prevent the next accidental commit | `gitleaks detect --redact --exit-code 1` in the `Preflight` stage; fails the build on a finding |
| Vault audit device | Attribute every runtime read | `vault audit enable file file_path=/vault/logs/audit.log` (production Vault, not dev mode) |

The PAT currently has `repo` + `write:packages`, which is broader than the task
needs; `docs/git-workflow.md` §4.2 and §8 already state that a deploy key or a
scoped fine-grained token is the production replacement.

## 6. Why the ESO objects are safe to commit

| Object | Contains | Can it leak? |
|---|---|---|
| `ClusterSecretStore` | Vault address, mount path, auth role name | No credential |
| `ExternalSecret` | Secret name, Vault key names, property names | No values |
| `Deployment` | Secret name and key name in `secretKeyRef` | No values |
| `Secret` (created by ESO) | The actual values | Lives only in etcd; never committed |
| Jenkins credential | The PAT | Encrypted Jenkins store; injected at runtime |

The only file that could leak a value is a `Secret` manifest, and none is
allowed in the repository. `.gitignore` also excludes local `.env` files and the
generated TLS material.

## 7. Secrets in logs — what the services actually do

- Logging is structured JSON (`core/logging.py`), one line per event.
- The request middleware logs `request_id`, `method`, `path`, `status_code` and
  `duration_ms`. It does **not** log headers, query strings, bodies or response
  bodies. A credential in an `Authorization` header therefore never reaches the
  log.
- Settings are logged at startup only as service name, version, environment and
  downstream URLs — no token fields exist in the settings model today.
- Trivy, bandit and pip-audit write JSON reports into `reports/`; they do not
  print environment variables.
- Docker build uses only `APP_VERSION` and `GIT_SHA` as build arguments. No
  secret is passed as a build argument, so no secret can be captured in an
  image layer or in `docker history`.

**Caveat to fix in P5:** the validation-error handler logs
`exc.errors()`, and Pydantic error objects include the rejected `input`. For the
current endpoints that input is a small JSON payload, but if payloads ever
contain PII or a secret, this line must be redacted. The safe pattern is to log
the field locations (`loc`) and the error types, never the input values.

## 8. Production hardening (documented, not deployed)

| Concern | POC (today) | Production |
|---|---|---|
| Vault storage | dev mode, in-memory, data lost on restart | Raft integrated storage, 3 replicas |
| Unseal | automatic (dev) | auto-unseal via cloud KMS/Transit |
| Auth | none yet; root token `root` | Kubernetes auth per environment, short TTL, bound service accounts |
| Store scope | one `ClusterSecretStore` planned | namespaced `SecretStore` per environment |
| Rotation | manual write + reloader | automated rotation (Vault DB/cloud engines) with lease renewal |
| Audit | none | audit device to immutable storage |
| Network | Vault reachable in-cluster | Vault on a separate cluster/namespace with a strict NetworkPolicy allow-list |
| Access to secrets in etcd | Kubernetes Secrets at rest | encryption-at-rest with KMS + etcd access restricted to the API server |
| CI credentials | long-lived PAT in Jenkins | OIDC federation, short-lived tokens, no static PAT |

A restart of the dev-mode Vault loses every value. ESO will then fail to sync
and the `ExternalSecret` condition becomes `SecretSynced=False`; re-seeding the
paths restores it. This is an accepted POC limitation, recorded in `handoff.md`
§16 and in the runbook.

## 9. Acceptance demonstration (P5 script)

Once wired, the proof is a sequence that never prints a value:

1. `kubectl -n bituach-prod get externalsecret` → `Ready=True`.
2. `kubectl -n bituach-prod get secret engine-secrets` → exists, owner is the
   `ExternalSecret`.
3. `kubectl -n bituach-prod exec deploy/engine -- sh -c 'test -n "$APP_SECRET_TOKEN" && echo present'`
   → `present`.
4. `grep -R "APP_SECRET_TOKEN=" .` → only the `secretKeyRef` reference and the
   Vault key name; no value.
5. `kubectl -n bituach-prod logs deploy/engine | grep -i <value>` → no match.
6. Rotate in Vault, wait one refresh interval, confirm the pod restarted (or
   the file changed) and the service still reports healthy.

Step 4 is the one a reviewer should run: it proves the value is not in the
repository, not that the author remembered to delete one file.
