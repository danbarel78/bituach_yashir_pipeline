"""Contract tests for the service metadata endpoints."""

from http import HTTPStatus

from fastapi.testclient import TestClient


def test_root_returns_service_name(client: TestClient) -> None:
    response = client.get("/")
    assert response.status_code == HTTPStatus.OK
    assert response.json() == {"service": "ingest"}


def test_version_returns_build_metadata(client: TestClient) -> None:
    response = client.get("/version")
    assert response.status_code == HTTPStatus.OK
    assert response.json() == {
        "service": "ingest",
        "version": "1.2.3",
        "gitSha": "abc1234",
        "environment": "test",
    }


def test_openapi_contract_is_generated(client: TestClient) -> None:
    document = client.get("/openapi.json").json()
    assert "/" in document["paths"]
    assert "/version" in document["paths"]
    assert "/healthz" in document["paths"]
    assert "/readyz" in document["paths"]
    assert document["paths"]["/"]["get"]["summary"] == "Return the service name"
