"""Shared dependencies resolved through FastAPI's injection system."""

from typing import Annotated

from fastapi import Depends

from ingest.core.config import Settings, get_settings

SettingsDep = Annotated[Settings, Depends(get_settings)]
