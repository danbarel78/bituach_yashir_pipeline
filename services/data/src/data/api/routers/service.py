"""Service metadata endpoints."""

from fastapi import APIRouter

from data.dependencies.common import SettingsDep
from data.schemas.service import ServiceNameResponse, VersionResponse
from data.services.service_info import build_service_name, build_version

router = APIRouter(tags=["service"])


@router.get(
    "/",
    response_model=ServiceNameResponse,
    summary="Return the service name",
    description="Contract endpoint required by the platform: identifies which service answered.",
)
async def read_service_name(settings: SettingsDep) -> ServiceNameResponse:
    """Return the logical service name."""
    return build_service_name(settings)


@router.get(
    "/version",
    response_model=VersionResponse,
    summary="Return build metadata",
    description="Exposes the immutable version and git commit baked into the image so a rollout can be verified.",
)
async def read_version(settings: SettingsDep) -> VersionResponse:
    """Return the version, git SHA and environment of the running pod."""
    return build_version(settings)
