"""Event ingestion endpoints."""

from fastapi import APIRouter

from ingest.dependencies.common import SettingsDep
from ingest.schemas.ingest import IngestAccepted, IngestRequest

router = APIRouter(tags=["ingest"])


@router.post(
    "/ingest",
    response_model=IngestAccepted,
    summary="Accept an event",
    description=(
        "Contract endpoint required by the platform: accepts a payload and acknowledges it. "
        "Payload values are never echoed or logged, so a secret sent here cannot leak."
    ),
)
async def accept_event(body: IngestRequest, settings: SettingsDep) -> IngestAccepted:
    """Acknowledge an event without persisting or logging its values."""
    return IngestAccepted(
        service=settings.service_name,
        accepted=True,
        source=body.source,
        payload_keys=sorted(body.payload),
    )
