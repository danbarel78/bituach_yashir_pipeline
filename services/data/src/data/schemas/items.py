"""Contracts for the sample data catalog."""

from pydantic import BaseModel, Field


class Item(BaseModel):
    """One record in the sample catalog."""

    id: int = Field(description="Stable identifier of the item.")
    name: str = Field(description="Human-readable item name.")
    category: str = Field(description="Grouping used by the catalog.")
    value: float = Field(description="Numeric value associated with the item.")


class ItemsResponse(BaseModel):
    """Payload returned by GET /items."""

    service: str = Field(description="Name of the service that answered the request.")
    count: int = Field(description="Number of items in this response.")
    items: list[Item] = Field(description="The sample catalog.")
