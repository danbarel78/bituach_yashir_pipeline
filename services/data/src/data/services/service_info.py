"""Business logic for service metadata."""

from data.core.config import Settings
from data.schemas.service import ServiceNameResponse, VersionResponse


def build_service_name(settings: Settings) -> ServiceNameResponse:
    """Return the logical service name."""
    return ServiceNameResponse(service=settings.service_name)


def build_version(settings: Settings) -> VersionResponse:
    """Return the build metadata injected into the image."""
    return VersionResponse(
        service=settings.service_name,
        version=settings.app_version,
        git_sha=settings.git_sha,
        environment=settings.environment,
    )
