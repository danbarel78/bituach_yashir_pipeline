"""Error contract tests: every failure must return the same JSON shape."""

from fastapi.testclient import TestClient


def test_unknown_path_returns_error_contract(client: TestClient) -> None:
    response = client.get("/does-not-exist")
    assert response.status_code == 404
    body = response.json()
    assert body["error"] == "http_404"
    assert body["detail"] == "Not Found"
    assert body["request_id"]


def test_wrong_method_returns_error_contract(client: TestClient) -> None:
    response = client.post("/")
    assert response.status_code == 405
    assert response.json()["error"] == "http_405"


def test_request_id_is_echoed(client: TestClient) -> None:
    response = client.get("/", headers={"x-request-id": "test-correlation-id"})
    assert response.headers["x-request-id"] == "test-correlation-id"
    assert response.json() == {"service": "data"}
