"""Contracts for the internal aggregation endpoint."""

from typing import Annotated

from pydantic import BaseModel, Field

from engine.schemas.service import DependencyStatus


class AggregateResponse(BaseModel):
    """Result of calling every internal dependency over the cluster network."""

    service: str = Field(description="Name of the service that answered the request.")
    downstream: Annotated[list[DependencyStatus], Field(description="Internal services reached from this pod.")] = []
    all_reachable: bool = Field(description="True when every internal dependency answered.")


class DownstreamTarget(BaseModel):
    """A single internal service this pod is allowed to call."""

    name: str = Field(description="Logical name of the internal service.")
    url: str = Field(description="ClusterIP base URL of the internal service.")
