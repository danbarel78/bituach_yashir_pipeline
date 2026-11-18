"""Internal channel tests: the engine calls its peers over ClusterIP."""

from http import HTTPStatus

import httpx
import pytest
from fastapi.testclient import TestClient

from engine.dependencies.common import get_http_client
from engine.main import create_app


def _offline_downstream(request: httpx.Request) -> httpx.Response:
    """Simulate an unreachable internal service."""
    raise httpx.ConnectError("connection refused", request=request)


def test_aggregate_reports_every_internal_service(client: TestClient) -> None:
    response = client.get("/aggregate")
    assert response.status_code == HTTPStatus.OK
    body = response.json()
    assert body["service"] == "engine"
    assert body["all_reachable"] is True
    assert [dependency["service"] for dependency in body["downstream"]] == ["data", "ingest"]


def test_readiness_degrades_when_a_dependency_is_down() -> None:
    application = create_app()
    transport = httpx.MockTransport(_offline_downstream)
    offline_client = httpx.AsyncClient(transport=transport)
    application.dependency_overrides[get_http_client] = lambda: offline_client

    with TestClient(application) as offline_test_client:
        response = offline_test_client.get("/readyz")

    application.dependency_overrides.clear()

    assert response.status_code == HTTPStatus.SERVICE_UNAVAILABLE
    body = response.json()
    assert body["status"] == "degraded"
    assert all(dependency["reachable"] is False for dependency in body["dependencies"])


@pytest.mark.parametrize("path", ["/readyz", "/aggregate"])
def test_healthy_dependencies_are_reported_reachable(client: TestClient, path: str) -> None:
    """A healthy dependency must be reported reachable and the endpoint must succeed."""
    response = client.get(path)
    assert response.status_code == HTTPStatus.OK
    body = response.json()
    dependencies = body["dependencies"] if path == "/readyz" else body["downstream"]
    assert all(dependency["reachable"] for dependency in dependencies)
