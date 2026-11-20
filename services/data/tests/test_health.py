"""Probe endpoint tests."""

from http import HTTPStatus

from fastapi.testclient import TestClient


def test_liveness_is_ok(client: TestClient) -> None:
    response = client.get("/healthz")
    assert response.status_code == HTTPStatus.OK
    assert response.json() == {"status": "ok", "service": "data"}


def test_readiness_is_ready(client: TestClient) -> None:
    response = client.get("/readyz")
    assert response.status_code == HTTPStatus.OK
    assert response.json() == {"status": "ready", "service": "data", "dependencies": []}
