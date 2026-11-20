"""Sample ingest endpoint tests."""

from http import HTTPStatus

from fastapi.testclient import TestClient


def test_ingest_accepts_payload_with_service_name(client: TestClient) -> None:
    response = client.post(
        "/ingest",
        json={"source": "engine", "payload": {"claim_id": "C-1", "amount": 42}},
    )

    assert response.status_code == HTTPStatus.OK
    body = response.json()
    assert body["service"] == "ingest"
    assert body["accepted"] is True
    assert body["source"] == "engine"
    assert body["payload_keys"] == ["amount", "claim_id"]


def test_ingest_never_echoes_payload_values(client: TestClient) -> None:
    """Values must not be reflected: a secret in the payload must not appear."""
    response = client.post(
        "/ingest",
        json={"source": "test", "payload": {"password": "super-secret-value"}},
    )

    assert response.status_code == HTTPStatus.OK
    assert "super-secret-value" not in response.text
    assert response.json()["payload_keys"] == ["password"]


def test_ingest_defaults_when_body_is_empty(client: TestClient) -> None:
    response = client.post("/ingest", json={})

    assert response.status_code == HTTPStatus.OK
    body = response.json()
    assert body["accepted"] is True
    assert body["source"] == "unknown"
    assert body["payload_keys"] == []


def test_ingest_rejects_negative_claim_amount(client: TestClient) -> None:
    response = client.post(
        "/ingest",
        json={"source": "test", "payload": {"claim_amount": -100}},
    )

    assert response.status_code == HTTPStatus.UNPROCESSABLE_ENTITY
    body = response.json()
    assert body["error"] == "validation_error"
    assert body["detail"] == "Request validation failed."


def test_ingest_accepts_non_negative_claim_amount(client: TestClient) -> None:
    response = client.post(
        "/ingest",
        json={"source": "test", "payload": {"claim_amount": 0}},
    )

    assert response.status_code == HTTPStatus.OK
    assert response.json()["accepted"] is True
