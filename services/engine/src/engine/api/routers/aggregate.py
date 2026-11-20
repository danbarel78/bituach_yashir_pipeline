"""Internal aggregation endpoint.

This endpoint exists to prove the internal ClusterIP channel: the engine calls
the data and ingest services and returns what they answered.
"""

from fastapi import APIRouter

from engine.dependencies.common import HttpClientDep, SettingsDep
from engine.schemas.aggregate import AggregateResponse
from engine.services.downstream import probe_all

router = APIRouter(tags=["aggregate"])


@router.get(
    "/aggregate",
    response_model=AggregateResponse,
    summary="Call every internal dependency",
    description="Calls the data and ingest services over ClusterIP and reports what each one answered.",
)
async def aggregate(settings: SettingsDep, client: HttpClientDep) -> AggregateResponse:
    """Return the result of calling every internal dependency."""
    downstream = await probe_all(client, settings)
    return AggregateResponse(
        service=settings.service_name,
        downstream=downstream,
        all_reachable=all(dependency.reachable for dependency in downstream),
    )
