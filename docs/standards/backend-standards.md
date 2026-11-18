# Backend Standards — Python and FastAPI

This document defines a proposed backend engineering baseline for Python services built with FastAPI. It is designed to complement the team's existing `python-standards` Tier-1 policy and the `python-craft` advisory skill.

> **Policy distinction:** The original Python standards are governed by the team's Confluence guidelines. The FastAPI standards in this document are a proposed backend extension, not Confluence requirements unless formally adopted.

## 1. Recommended standards architecture

Keep three review responsibilities distinct:

| Layer | Responsibility | Reporting |
|---|---|---|
| Tier 1 — `python-standards` | Mandatory Python team policy: tooling, project structure, configuration, typing, quality tools, testing, pre-commit, CI/CD and version management | PASS / FAIL / N/A; policy compliance |
| Backend extension — FastAPI | API-specific engineering baseline: routing, contracts, dependencies, async behavior, lifecycle, configuration, security, testing and OpenAPI | PASS / FAIL / N/A; report separately as a proposed baseline |
| Advisory — `python-craft` | Clean code, abstractions, maintainability, performance, error handling and logging practices not mandated by Tier 1 | Advisory findings / warnings |

The standards auditor verifies compliance. The craft reviewer evaluates implementation quality. Neither replaces the other.

## 2. FastAPI Backend Standards

### 2.1 Application structure

- Provide a dedicated application entry point, such as `main.py`.
- Use `APIRouter` to organize endpoints into logical modules.
- Separate routers, schemas, services, dependencies and configuration into appropriate modules.
- Avoid implementing substantial business logic directly inside path operation functions.
- Register routers centrally in the application entry point.
- Keep application initialization separate from business logic.
- Apply the structure proportionately; do not create empty modules or directories without a purpose.

Suggested project structure:

```text
src/
└── package_name/
    ├── __init__.py
    ├── main.py
    ├── api/
    │   ├── __init__.py
    │   └── routers/
    │       ├── __init__.py
    │       └── health.py
    ├── schemas/
    │   ├── __init__.py
    │   └── health.py
    ├── services/
    │   ├── __init__.py
    │   └── health_service.py
    ├── dependencies/
    │   ├── __init__.py
    │   └── common.py
    └── core/
        ├── __init__.py
        └── config.py
```

This is a suggested layout, not a requirement to create every directory in every service.

### 2.2 API contracts and validation

- Use Pydantic models for API request bodies.
- Define explicit response models using `response_model` or appropriate return type annotations.
- Validate external input at API boundaries.
- Do not expose internal database models directly as public API contracts.
- Use separate request and response schemas when their responsibilities differ.
- Avoid untyped dictionaries for structured API contracts.
- Use Pydantic models for configuration and external data validation.

### 2.3 Dependency injection

- Use FastAPI's native `Depends` mechanism for shared dependencies.
- Prefer `Annotated` for dependency declarations.
- Keep dependencies reusable and independently testable.
- Use dependencies for database sessions, authentication, authorization and shared request context.
- Avoid creating application-wide resources independently inside individual endpoint handlers.

Example:

```python
from typing import Annotated

from fastapi import Depends, FastAPI

app = FastAPI()


async def get_current_user() -> str:
    return "user"


@app.get("/users/me")
async def read_current_user(
    user: Annotated[str, Depends(get_current_user)],
) -> dict[str, str]:
    return {"user": user}
```

### 2.4 Async and concurrency

- Use `async def` when calling asynchronous libraries.
- Await asynchronous operations.
- Do not execute blocking I/O directly inside asynchronous endpoint handlers.
- Use synchronous `def` handlers when using synchronous I/O libraries, where appropriate.
- Review CPU-intensive operations separately from asynchronous request handling.
- Do not assume that declaring a function `async` automatically makes its internal operations non-blocking.

### 2.5 Application lifecycle

- Prefer FastAPI's `lifespan` mechanism for application startup and shutdown.
- Initialize and release shared resources through the application lifecycle.
- Ensure database connections, clients and other shared resources are closed properly.
- Avoid introducing new startup/shutdown implementations based on deprecated event patterns.

### 2.6 Configuration and secrets

- Use environment variables for deployment-specific configuration.
- Use Pydantic Settings for validated application settings.
- Do not hardcode credentials, API keys, tokens or environment-specific URLs.
- Do not commit secrets to source control.
- Keep configuration separate from application business logic.

### 2.7 Error handling

- Use appropriate HTTP status codes.
- Use `HTTPException` for expected HTTP-level errors.
- Implement centralized exception handlers when consistent API error responses are required.
- Do not expose internal stack traces or sensitive implementation details in production responses.

### 2.8 API security

- Use FastAPI security utilities and dependencies for authentication and authorization.
- Enforce authorization at the appropriate endpoint or router level.
- Validate all external input.
- Do not expose sensitive fields through response models.
- Ensure secrets and authentication tokens are not included in logs or API responses.

### 2.9 Testing

- Use `TestClient` for synchronous API integration tests.
- Use `httpx.AsyncClient` with `ASGITransport` for asynchronous tests when appropriate.
- Test successful responses and expected error responses.
- Test request validation and response contracts.
- Test authentication and authorization behavior.
- Test dependency overrides where external resources need to be isolated.
- Test application lifespan behavior when startup/shutdown resources are involved.
- Mock external services at appropriate integration boundaries.

### 2.10 API documentation

- Maintain meaningful endpoint descriptions and tags.
- Use Pydantic schemas to generate accurate OpenAPI contracts.
- Document expected HTTP status codes and error responses.
- Ensure API documentation does not expose internal or sensitive information.

## 3. FastAPI audit reporting

The FastAPI section must be reported separately from the original Tier-1 Confluence compliance report.

For each applicable check, use:

- **PASS** — the project satisfies the check.
- **FAIL** — the project does not satisfy the check; include `file:line` evidence where possible.
- **N/A** — the check does not apply to the project.

Until formally adopted as team policy:

- Identify the section as **PROPOSED BACKEND BASELINE**.
- Do not include its failures in the Tier-1 Confluence FAIL count.
- Do not represent proposed standards as Confluence requirements.
- Clearly identify deviations as proposed-baseline gaps.
- If the project does not use FastAPI, mark the section N/A.

## 4. Official technical references

Use official documentation as the technical source of truth. Prefer documentation compatible with the FastAPI and Pydantic versions installed in the project.

1. **Bigger Applications / APIRouter**  
   https://fastapi.tiangolo.com/tutorial/bigger-applications/

2. **Dependencies and dependency injection**  
   https://fastapi.tiangolo.com/tutorial/dependencies/

3. **Response models and validation**  
   https://fastapi.tiangolo.com/tutorial/response-model/

4. **Async and await**  
   https://fastapi.tiangolo.com/async/

5. **Application lifespan**  
   https://fastapi.tiangolo.com/advanced/events/

6. **Testing**  
   https://fastapi.tiangolo.com/tutorial/testing/

7. **Asynchronous testing**  
   https://fastapi.tiangolo.com/advanced/async-tests/

8. **Security**  
   https://fastapi.tiangolo.com/tutorial/security/

9. **Pydantic Settings**  
   https://docs.pydantic.dev/latest/concepts/pydantic_settings/

10. **FastAPI learning and AI-agent resources**  
    https://fastapi.tiangolo.com/learn/

## 5. Runtime and development dependencies

FastAPI and the ASGI server belong in the runtime dependencies. Testing and code-quality tools belong in the development dependency group.

Example starting point for `pyproject.toml`:

```toml
[project]
dependencies = [
    "fastapi",
    "uvicorn[standard]",
    "pydantic",
    "pydantic-settings",
]

[project.optional-dependencies]
dev = [
    "ruff",
    "mypy",
    "pyright",
    "pytest",
    "pytest-cov",
    "httpx",
    "pre-commit",
]
```

Guidance:

- Pin and resolve dependency versions through the project's existing `uv` workflow.
- Commit `uv.lock` and keep it synchronized with `pyproject.toml`.
- Add database drivers, ORM packages and other infrastructure dependencies according to the actual application.
- Keep runtime dependencies separate from development-only dependencies.
- Confirm compatibility between FastAPI, Pydantic, Starlette, the ASGI server and any other framework integrations.

## 6. Suggested auditor prompt extension

Append the following to the existing `python-standards` auditor prompt:

```text
16. FastAPI Backend Standards (Proposed Backend Extension)

For projects using FastAPI, inspect the application against the FastAPI
Backend Standards section in the calling skill.

Report:
- Application structure and APIRouter organization.
- Pydantic request/response validation.
- Dependency injection using Depends and Annotated.
- Correct async/sync execution.
- Application lifecycle management.
- Configuration and secrets management.
- HTTP error handling.
- API security.
- Endpoint and integration testing.
- OpenAPI documentation.

Do not assume every Python project uses FastAPI. If FastAPI is not
present or applicable, mark the section N/A.

Report this section separately from the Tier-1 Confluence compliance
summary. These are proposed backend standards and must not be counted
as Confluence policy failures.

Use the official FastAPI and Pydantic documentation references
provided in the backend standards document when verifying technical
behavior.
```

The auditor should not silently change the original 15 Confluence sections or their policy counts when this extension is added.

## 7. Recommended adoption approach

1. Add this document to the repository, for example under `docs/standards/backend-standards.md`.
2. Reference it from the `python-standards` skill as the FastAPI backend extension.
3. Keep the original Confluence policy and its freshness verification unchanged.
4. Review the proposed checks with the team.
5. Once approved, decide which checks become mandatory team policy and update the canonical guidelines accordingly.

## 8. Optional official FastAPI agent skill

FastAPI also provides AI-agent learning resources. Evaluate the official material alongside the custom OpenCode skills rather than duplicating framework implementation guidance unnecessarily:

https://fastapi.tiangolo.com/learn/

The custom standards document should remain the team's policy and audit reference; framework-provided agent guidance can supplement implementation work.
