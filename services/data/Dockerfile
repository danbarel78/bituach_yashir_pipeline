# syntax=docker/dockerfile:1.7
# Multi-stage build: uv resolves the locked dependencies, the runtime stage carries only the venv.
FROM python:3.12-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.13.9 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY pyproject.toml uv.lock README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY src ./src
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-editable

FROM python:3.12-slim AS runtime

# Apply Debian security updates that landed after this base image was built.
# Without this the image scan fails on a base-package CVE we can fix, and
# "ignore-unfixed" alone would not be honest.
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH" \
    SERVICE_NAME=data

# Fixed numeric UID/GID so securityContext.runAsNonRoot can be verified by
# the kubelet (a named USER cannot be checked and the pod is rejected).
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid 10001 \
       --home-dir /app --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder --chown=app:app /app/.venv /app/.venv

ARG APP_VERSION=0.0.0
ARG GIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION} \
    GIT_SHA=${GIT_SHA}

USER 10001:10001

EXPOSE 8000

CMD ["uvicorn", "data.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
