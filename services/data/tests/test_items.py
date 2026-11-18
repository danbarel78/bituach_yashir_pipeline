"""Catalog endpoint tests."""

from http import HTTPStatus

from fastapi.testclient import TestClient


def test_items_returns_catalog_with_service_name(client: TestClient) -> None:
    response = client.get("/items")

    assert response.status_code == HTTPStatus.OK
    body = response.json()
    assert body["service"] == "data"
    assert body["count"] == len(body["items"])
    assert body["count"] > 0


def test_items_are_deterministic(client: TestClient) -> None:
    """The catalog must be stable so smoke tests can assert on it."""
    first = client.get("/items").json()
    second = client.get("/items").json()

    assert first == second


def test_item_shape(client: TestClient) -> None:
    item = client.get("/items").json()["items"][0]

    assert set(item) == {"id", "name", "category", "value"}
    assert isinstance(item["id"], int)
    assert isinstance(item["name"], str)
