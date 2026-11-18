"""Kubernetes probe endpoints."""

from fastapi import APIRouter, Response

from engine.dependencies.common import HttpClientDep, SettingsDep
from engine.schemas.service import HealthResponse, ReadinessResponse
from engine.services.downstream import probe_all

router = APIRouter(tags=["health"])


@router.get(
    "/healthz",
    response_model=HealthResponse,
    summary="Liveness probe",
    description="Reports process liveness only. It never calls downstream services, so a slow dependency cannot restart the pod.",
)
async def liveness(settings: SettingsDep) -> HealthResponse:
    """Return liveness without touching downstream services."""
    return HealthResponse(status="ok", service=settings.service_name)


@router.get(
    "/readyz",
    response_model=ReadinessResponse,
    responses={503: {"model": ReadinessResponse, "description": "One or more internal dependencies are unreachable."}},
    summary="Readiness probe",
    description="Reports whether the pod can receive traffic. The engine calls its internal dependencies over ClusterIP.",
)
async def readiness(
    settings: SettingsDep,
    client: HttpClientDep,
    response: Response,
) -> ReadinessResponse:
    """Return readiness after checking every internal dependency."""
    dependencies = await probe_all(client, settings)
    all_reachable = all(dependency.reachable for dependency in dependencies)
    if not all_reachable:
        response.status_code = 503
    return ReadinessResponse(
        status="ready" if all_reachable else "degraded",
        service=settings.service_name,
        dependencies=dependencies,
    )
