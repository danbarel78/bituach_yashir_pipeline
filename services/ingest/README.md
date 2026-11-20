# ingest service

FastAPI microservice that reports its own name. Part of the Bituach Yashir platform POC.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | Contract endpoint: `{"service": "ingest"}` |
| GET | `/version` | Immutable version, git SHA and environment baked into the image |
| GET | `/healthz` | Liveness probe (never checks dependencies) |
| GET | `/readyz` | Readiness probe |
| GET | `/docs` | OpenAPI UI |
| GET | `/openapi.json` | OpenAPI contract |

## Configuration

All configuration arrives through environment variables. No secrets are read here.

| Variable | Default | Purpose |
|---|---|---|
| `SERVICE_NAME` | `ingest` | Logical service name |
| `ENVIRONMENT` | `dev` | Deployment environment |
| `APP_VERSION` | `0.0.0` | Release version injected at build time |
| `GIT_SHA` | `unknown` | Commit SHA injected at build time |
| `LOG_LEVEL` | `INFO` | Root log level |

## Run locally

```bash
uv sync --frozen
uv run uvicorn ingest.main:app --reload --port 8002
```

## Test

```bash
uv run pytest --cov --cov-report=term-missing
uv run ruff check .
uv run mypy src
uv run pyright
```

## Build the image

```bash
docker build --build-arg APP_VERSION=1.0.0 --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t bituach-ingest:local .
```

## Notes

- The package metadata version is intentionally `0.0.0`; the deployed version is injected at build time from the repository `base_version.json`, which is the single source of truth.
- Logs are JSON to stdout and never contain request bodies, credentials or tokens.
