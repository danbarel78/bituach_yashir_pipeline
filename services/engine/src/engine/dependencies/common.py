"""Shared dependencies resolved through FastAPI's injection system."""

from typing import Annotated

import httpx
from fastapi import Depends, Request

from engine.core.config import Settings, get_settings

SettingsDep = Annotated[Settings, Depends(get_settings)]


def get_http_client(request: Request) -> httpx.AsyncClient:
    """Return the shared async client created during application startup."""
    client: httpx.AsyncClient = request.app.state.http_client
    return client


HttpClientDep = Annotated[httpx.AsyncClient, Depends(get_http_client)]
