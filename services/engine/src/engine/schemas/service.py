"""Public API contracts."""

from typing import Annotated

from pydantic import BaseModel, Field


class ServiceNameResponse(BaseModel):
    """Response for the root endpoint."""

    service: str = Field(description="Name of the service that answered the request.")


class VersionResponse(BaseModel):
    """Build metadata baked into the running image.

    The field is declared as ``git_sha`` so Python callers and type checkers use
    the snake_case name, while ``serialization_alias`` keeps the public JSON
    contract camelCase (``gitSha``).
    """

    service: str = Field(description="Name of the service that answered the request.")
    version: str = Field(description="Immutable release version baked into the image.")
    git_sha: str = Field(serialization_alias="gitSha", description="Git commit baked into the image.")
    environment: str = Field(description="Deployment environment the pod runs in.")


class HealthResponse(BaseModel):
    """Liveness result."""

    status: str = Field(description="Always 'ok' when the process is alive.")
    service: str = Field(description="Name of the service that answered the request.")


class DependencyStatus(BaseModel):
    """Reachability of a single internal dependency."""

    service: str = Field(description="Logical name of the dependency.")
    reachable: bool = Field(description="Whether the dependency answered successfully.")
    detail: str | None = Field(default=None, description="Failure reason when the dependency is unreachable.")


class ReadinessResponse(BaseModel):
    """Readiness result, including internal dependencies."""

    status: str = Field(description="'ready' or 'degraded'.")
    service: str = Field(description="Name of the service that answered the request.")
    dependencies: Annotated[list[DependencyStatus], Field(description="Internal dependencies checked before reporting ready.")] = []
