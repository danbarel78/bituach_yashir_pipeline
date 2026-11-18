"""Contracts for the ingest endpoint."""

from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class IngestRequest(BaseModel):
    """A payload submitted to the ingest service."""

    model_config = ConfigDict(populate_by_name=True)

    source: str = Field(
        default="unknown",
        description="Producer of the event, used for routing and troubleshooting.",
    )
    payload: dict[str, Any] = Field(
        default_factory=dict,
        description="Opaque event body. Echoed back only as keys, never as values.",
    )


class IngestAccepted(BaseModel):
    """Acknowledgement returned by POST /ingest."""

    model_config = ConfigDict(populate_by_name=True)

    service: str = Field(description="Name of the service that accepted the event.")
    accepted: bool = Field(description="True when the event was accepted.")
    source: str = Field(description="Producer as received, for correlation.")
    payload_keys: list[str] = Field(
        description="Keys present in the payload. Values are never echoed, so secrets cannot leak into logs or responses."
    )
