"""Internal service calls over the cluster network.

The engine is the only service that talks to its peers. Every call goes to a
ClusterIP Service DNS name, which is the internal channel the platform design
documents. No call leaves the cluster.
"""

import asyncio
import logging

import httpx

from engine.core.config import Settings
from engine.schemas.aggregate import DownstreamTarget
from engine.schemas.service import DependencyStatus, ServiceNameResponse

logger = logging.getLogger(__name__)


def downstream_targets(settings: Settings) -> list[DownstreamTarget]:
    """Return the internal services this pod is allowed to call."""
    return [
        DownstreamTarget(name="data", url=settings.data_service_url),
        DownstreamTarget(name="ingest", url=settings.ingest_service_url),
    ]


async def probe_target(
    client: httpx.AsyncClient,
    target: DownstreamTarget,
    timeout_seconds: float,
) -> DependencyStatus:
    """Call one internal service and report whether it answered."""
    try:
        response = await client.get(f"{target.url}/", timeout=timeout_seconds)
        response.raise_for_status()
        payload = ServiceNameResponse.model_validate(response.json())
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning(
            "downstream_unreachable",
            extra={"target": target.name, "error_type": type(exc).__name__},
        )
        return DependencyStatus(service=target.name, reachable=False, detail=str(exc))
    return DependencyStatus(service=payload.service, reachable=True)


async def probe_all(
    client: httpx.AsyncClient,
    settings: Settings,
) -> list[DependencyStatus]:
    """Probe every internal dependency concurrently."""
    return list(
        await asyncio.gather(
            *(probe_target(client, target, settings.downstream_timeout_seconds) for target in downstream_targets(settings)),
        ),
    )
