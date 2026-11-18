"""Public API contracts."""

from pydantic import BaseModel, ConfigDict, Field


class ServiceNameResponse(BaseModel):
    """Response for the root endpoint."""

    service: str = Field(description="Name of the service that answered the request.")


class VersionResponse(BaseModel):
    """Build metadata baked into the running image."""

    model_config = ConfigDict(populate_by_name=True)

    service: str = Field(description="Name of the service that answered the request.")
    version: str = Field(description="Immutable release version baked into the image.")
    git_sha: str = Field(alias="gitSha", description="Git commit baked into the image.")
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
    """Readiness result, including internal dependencies when the service has any."""

    status: str = Field(description="'ready' or 'degraded'.")
    service: str = Field(description="Name of the service that answered the request.")
    dependencies: list[DependencyStatus] = Field(
        default_factory=list,
        description="Internal dependencies checked before reporting ready.",
    )
