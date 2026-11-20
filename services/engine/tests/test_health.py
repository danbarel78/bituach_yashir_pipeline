"""Probe endpoint tests."""

from http import HTTPStatus

from fastapi.testclient import TestClient


def test_liveness_is_ok(client: TestClient) -> None:
    response = client.get("/healthz")
    assert response.status_code == HTTPStatus.OK
    assert response.json() == {"status": "ok", "service": "engine"}


def test_readiness_is_ready_when_dependencies_answer(client: TestClient) -> None:
    response = client.get("/readyz")
    assert response.status_code == HTTPStatus.OK
    body = response.json()
    assert body["status"] == "ready"
    assert body["service"] == "engine"
    assert [dependency["service"] for dependency in body["dependencies"]] == ["data", "ingest"]
    assert all(dependency["reachable"] for dependency in body["dependencies"])
