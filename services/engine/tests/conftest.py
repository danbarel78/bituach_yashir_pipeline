"""Shared test fixtures."""

from collections.abc import Iterator

import httpx
import pytest
from fastapi.testclient import TestClient

from engine.core.config import get_settings
from engine.dependencies.common import get_http_client
from engine.main import create_app


def _fake_downstream(request: httpx.Request) -> httpx.Response:
    """Answer like the real internal services do."""
    host = request.url.host
    return httpx.Response(200, json={"service": host})


@pytest.fixture(autouse=True)
def _environment(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Pin configuration for every test and clear the settings cache."""
    monkeypatch.setenv("SERVICE_NAME", "engine")
    monkeypatch.setenv("ENVIRONMENT", "test")
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    monkeypatch.setenv("GIT_SHA", "abc1234")
    monkeypatch.setenv("LOG_LEVEL", "WARNING")
    monkeypatch.setenv("DATA_SERVICE_URL", "http://data:8000")
    monkeypatch.setenv("INGEST_SERVICE_URL", "http://ingest:8000")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def client() -> Iterator[TestClient]:
    """Return a test client whose internal calls never leave the process."""
    application = create_app()
    transport = httpx.MockTransport(_fake_downstream)
    fake_client = httpx.AsyncClient(transport=transport)

    application.dependency_overrides[get_http_client] = lambda: fake_client
    with TestClient(application) as test_client:
        yield test_client
    application.dependency_overrides.clear()
