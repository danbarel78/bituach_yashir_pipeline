# Changelog

All notable changes to this project. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) and are
generated from Conventional Commits by `scripts/release.sh`.

`v0.0.0` below is the pre-release POC baseline, not a tagged release. The first
real release (`v1.0.0`) will be prepended above it when `scripts/release.sh` runs
on `main`.

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
