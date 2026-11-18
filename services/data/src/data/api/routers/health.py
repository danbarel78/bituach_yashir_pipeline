"""Kubernetes probe endpoints."""

from fastapi import APIRouter

from data.dependencies.common import SettingsDep
from data.schemas.service import HealthResponse, ReadinessResponse

router = APIRouter(tags=["health"])


@router.get(
    "/healthz",
    response_model=HealthResponse,
    summary="Liveness probe",
    description="Reports process liveness only. It never checks dependencies, so a slow dependency cannot restart the pod.",
)
async def liveness(settings: SettingsDep) -> HealthResponse:
    """Return liveness without touching downstream services."""
    return HealthResponse(status="ok", service=settings.service_name)


@router.get(
    "/readyz",
    response_model=ReadinessResponse,
    summary="Readiness probe",
    description="Reports whether the pod can receive traffic. This service has no internal dependencies.",
)
async def readiness(settings: SettingsDep) -> ReadinessResponse:
    """Return readiness; the data service has no downstream dependencies."""
    return ReadinessResponse(status="ready", service=settings.service_name)
