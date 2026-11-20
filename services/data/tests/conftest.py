"""Shared test fixtures."""

from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from data.core.config import get_settings
from data.main import create_app


@pytest.fixture(autouse=True)
def _environment(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Pin configuration for every test and clear the settings cache."""
    monkeypatch.setenv("SERVICE_NAME", "data")
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    monkeypatch.setenv("GIT_SHA", "abc1234")
    monkeypatch.setenv("LOG_LEVEL", "WARNING")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def client() -> Iterator[TestClient]:
    """Return a test client bound to a freshly created application."""
    with TestClient(create_app()) as test_client:
        yield test_client
