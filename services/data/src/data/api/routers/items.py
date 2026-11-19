"""Catalog endpoints."""

from fastapi import APIRouter

from data.dependencies.common import SettingsDep
from data.schemas.items import ItemsResponse
from data.services.item_catalog import build_items

router = APIRouter(tags=["catalog"])


@router.get(
    "/items",
    response_model=ItemsResponse,
    summary="Return the sample catalog",
    description=("Contract endpoint required by the platform: proves the service can serve domain data, not just its own metadata."),
)
async def read_items(settings: SettingsDep) -> ItemsResponse:
    """Return the static sample catalog."""
    return build_items(settings.service_name)
