# Contributing to the data service

## Setup

```bash
uv sync --frozen
uv run pre-commit install --hook-type pre-commit --hook-type pre-push
```

`uv` is the only supported dependency manager. `uv.lock` is committed and must stay in sync with `pyproject.toml`.

## Layout

```text
src/data/
  main.py            application factory and lifespan
  core/              configuration, logging, error handling
  api/routers/       HTTP route modules
  schemas/           Pydantic contracts
  services/          business logic
  dependencies/      shared FastAPI dependencies
tests/               pytest suite mirroring src/
```

## Quality gates

```bash
uv run ruff check .        # lint
uv run ruff format --check .
uv run mypy src            # strict
uv run pyright             # strict
uv run pytest --cov        # coverage >= 80%
```

All five gates run in the Jenkins pipeline. A failing gate blocks the build.

## Pull requests

1. Branch from `develop` using `feature/<short-description>`.
2. Use Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `test:`).
3. Open the PR against `develop` from the GitHub web UI (no `gh` CLI required).
4. Keep the PR small and the description explicit about risk.

See the repository root `docs/git-workflow.md` for the full GitFlow model and release procedure.
