# Changelog

All notable changes to this project. Generated from Conventional Commits (Keep a Changelog format).

## [v1.0.0] - 2026-11-20

### Added
- feat(ci): stage release pins on develop and simplify the delivery runbook
- feat(ci): accept fix/* branches and fetch tags for release builds
- feat(ci): poll every branch once a minute
- feat(ci): add containerised Jenkins pipeline with digest write-back
- feat(gitops): pin service images by digest from GHCR
- feat(services): add data /items and ingest /ingest endpoints, expose per-service hostnames
- feat(infra): add Terraform environment modules and GitOps base/overlays with app-of-apps
- feat(platform): install ingress, metrics-server, Argo CD, Vault and ESO with bootstrap scripts
- feat: add engine, data, ingest FastAPI services

### Fixed
- fix(ci): scan branches only from the folder to avoid duplicate builds
- fix(ci): only honour [skip ci] on integration branches
- fix(ingest): reject negative claim amounts
- fix(release): require a clean working tree
- fix(ci): force an Argo CD refresh before waiting for the new revision
- fix(ci): wait for the pushed revision and resolve the smoke host over IPv4
- fix(ci): isolate the Trivy cache per build
- fix(ci): install buildx and grant the socket group to the controller
- fix(images): apply Debian security updates and fail only on fixable CVEs
- fix(ci): build with BuildKit so cache mounts in the Dockerfiles work
- fix(ci): exclude the local project from the dependency audit export
- fix(services): pin container user to numeric uid 10001 so runAsNonRoot is verifiable
- fix(data): repair duplicate pyproject keys and undefined names blocking quality gates

### Chore
- chore(gitops): pin 1.0.0-rc.2+830c0c3 [skip ci]
- chore(gitops): pin 0.0.1-dev.12+36666d6 [skip ci]
- chore(gitops): pin 0.0.1-dev.9+f31ed9e [skip ci]
- chore(gitops): pin 0.0.1-dev.5+877242a [skip ci]
- chore(gitops): pin 0.0.1-dev.4+c04dd43 [skip ci]
- chore(gitops): pin 0.0.1-dev.2+7d4e031 [skip ci]
- chore: scaffold version tooling and project baseline
## [v0.0.0] - 2026-11-19

### Added

- Three FastAPI services (`engine`, `data`, `ingest`) with `/healthz`, `/readyz`,
  `/version`, `/aggregate`, `/items` and `/ingest`, structured JSON logging and
  80%+ test coverage.
- Multi-stage, non-root container images (UID 10001) with `APP_VERSION` and
  `GIT_SHA` baked in at build time.
- Terraform modules for namespace, ResourceQuota + LimitRange, RBAC and
  ServiceAccounts, NetworkPolicy and HPA, composed into dev, staging and prod
  environments.
- Kustomize base + overlays, Argo CD app-of-apps, digest-pinned deployments and
  a manual approval gate for production.
- Containerised Jenkins multibranch pipeline: version, lint, type checks, tests,
  bandit, pip-audit, image build, Trivy scan, GHCR push, GitOps digest write-back,
  Argo CD wait and post-deploy smoke test.
- Platform layer installed by `scripts/bootstrap.sh`: ingress-nginx, metrics-server,
  Argo CD, Vault (dev mode) and External Secrets Operator.
- Self-signed TLS for the local hosts, generated at bootstrap and never committed.
- `scripts/verify.sh` (platform assertions) and `scripts/smoke-test.sh`
  (per-environment endpoint checks).
- Documentation for versioning, secrets design, environment topology and
  requirements coverage (`docs/versioning.md`, `docs/secrets.md`,
  `docs/environment-topology.md`, `docs/requirements-coverage.md`).

### Changed

- Images are promoted by digest, not by mutable tag; `latest` and `local` are
  rejected by the pipeline preflight guard.
- Version computation is branch-driven from `base_version.json`
  (`ci/scripts/version.py`) with SemVer validation and monotonicity guards.
- GHCR packages published publicly so the POC needs no `imagePullSecret`;
  the private-registry variant is documented.

### Fixed

- Duplicate `[tool.pyright]` keys and undefined names blocking the data service
  quality gates.
- Container user pinned to a numeric UID so `runAsNonRoot` is enforceable.
- Debian security updates applied in the runtime image; Trivy fails only on
  fixable HIGH/CRITICAL findings.
- Trivy cache isolated per build to avoid concurrent scan lock failures.
- BuildKit enabled in CI and buildx installed in the Jenkins controller.
- Smoke test waits for the exact pushed Git revision and resolves the ingress
  host over IPv4.

### Security

- Vault, External Secrets Operator and the Vault UI are installed and verified;
  runtime secret injection is specified in `docs/secrets.md` and remains the
  outstanding implementation step (P5).
- GHCR and Git credentials are consumed only through Jenkins `withCredentials`
  and `--password-stdin`, never echoed or committed.
