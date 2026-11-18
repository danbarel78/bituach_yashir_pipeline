# Makefile - developer entry point for the three services.
# Tooling runs in WSL2 `Ubuntu` (see docs/environment-topology.md):
# `wsl` then `make <target>` from the repository root.

SERVICES := engine data ingest

.PHONY: install lint format typecheck test coverage security version \
        docker-build smoke clean jenkins-build jenkins-up jenkins-down jenkins-logs

## install: uv sync every service (runtime + dev dependencies)
install:
	@for s in $(SERVICES); do \
		echo "==> $$s: uv sync"; \
		(cd services/$$s && uv sync --extra dev) || exit 1; \
	done

## lint: ruff check every service
lint:
	@for s in $(SERVICES); do \
		echo "==> $$s: ruff"; \
		(cd services/$$s && uv run ruff check .) || exit 1; \
	done

## format: ruff format check every service (non-mutating)
format:
	@for s in $(SERVICES); do \
		echo "==> $$s: ruff format --check"; \
		(cd services/$$s && uv run ruff format --check .) || exit 1; \
	done

## typecheck: mypy strict every service
typecheck:
	@for s in $(SERVICES); do \
		echo "==> $$s: mypy"; \
		(cd services/$$s && uv run mypy .) || exit 1; \
	done

## test: pytest every service (with coverage, fails under 80%)
test: coverage

## coverage: pytest + coverage gate (fail_under = 80 in pyproject.toml)
coverage:
	@for s in $(SERVICES); do \
		echo "==> $$s: pytest"; \
		(cd services/$$s && uv run pytest --cov) || exit 1; \
	done

## security: bandit + pip-audit every service (POC shortcut; CI runs the real gates)
security:
	@for s in $(SERVICES); do \
		echo "==> $$s: bandit"; \
		(cd services/$$s && uv run bandit -r src -q) || exit 1; \
	done

## version: print the computed pipeline version for the current branch
version:
	python3 ci/scripts/version.py

## docker-build: build local :local images for all services
docker-build:
	@for s in $(SERVICES); do \
		echo "==> $$s: docker build"; \
		docker build -t ghcr.io/danbarel78/bituach-yashir-$$s:local services/$$s || exit 1; \
	done

## smoke: hit / on all three locally running services (port-forwarded or published)
smoke:
	@for s in $(SERVICES); do \
		echo "==> $$s: GET /"; \
		curl -fsS "http://localhost:8000/" || exit 1; \
	done

## clean: remove caches and coverage artifacts
clean:
	@for s in $(SERVICES); do \
		(cd services/$$s && rm -rf .pytest_cache .mypy_cache .ruff_cache .coverage htmlcov); \
	done

## jenkins-build: build the Jenkins controller image
jenkins-build:
	docker build -t bituach-yashir-jenkins:local ci/docker/jenkins

## jenkins-up: start the controller (http://localhost:8080, admin / admin)
jenkins-up:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ci/jenkins.ps1 up

## jenkins-down: remove the controller, keep JENKINS_HOME (jobs/credentials)
jenkins-down:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File ci/jenkins.ps1 down

## jenkins-logs: follow controller logs
jenkins-logs:
	docker logs -f bituach-jenkins
