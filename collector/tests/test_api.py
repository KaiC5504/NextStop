import pytest
from fastapi.testclient import TestClient

from nextstop_collector.api import app


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


class TestAuth:
    def test_missing_token_is_rejected(self, client):
        response = client.post(
            "/observations", json={"event": "boarded", "corridor": "chatswood-usyd"}
        )
        assert response.status_code == 401

    def test_wrong_token_is_rejected(self, client):
        response = client.post(
            "/observations",
            json={"event": "boarded", "corridor": "chatswood-usyd"},
            headers={"X-NextStop-Token": "nope"},
        )
        assert response.status_code == 401

    def test_health_needs_no_token(self, client):
        assert client.get("/health").status_code == 200


class TestObservations:
    def test_boarding_is_stored_and_returned(self, client, auth_headers):
        response = client.post(
            "/observations",
            json={"event": "boarded", "corridor": "chatswood-usyd"},
            headers=auth_headers,
        )
        assert response.status_code == 200
        body = response.json()
        assert body["event"] == "boarded"
        assert body["corridor"] == "chatswood-usyd"
        assert body["id"] > 0

    def test_stored_observation_appears_in_recent(self, client, auth_headers):
        client.post(
            "/observations",
            json={"event": "arrived", "corridor": "usyd-chatswood", "note": "delayed"},
            headers=auth_headers,
        )
        recent = client.get("/observations/recent", headers=auth_headers).json()
        assert any(r["event"] == "arrived" and r["corridor"] == "usyd-chatswood" for r in recent)

    def test_unknown_event_is_rejected(self, client, auth_headers):
        response = client.post(
            "/observations",
            json={"event": "teleported", "corridor": "chatswood-usyd"},
            headers=auth_headers,
        )
        assert response.status_code == 422

    def test_naive_recorded_at_is_rejected(self, client, auth_headers):
        response = client.post(
            "/observations",
            json={
                "event": "boarded",
                "corridor": "chatswood-usyd",
                "recorded_at": "2026-07-27T09:03:00",
            },
            headers=auth_headers,
        )
        assert response.status_code == 422

    def test_explicit_timestamp_is_kept(self, client, auth_headers):
        response = client.post(
            "/observations",
            json={
                "event": "boarded",
                "corridor": "chatswood-central",
                "recorded_at": "2026-07-27T09:03:00+10:00",
            },
            headers=auth_headers,
        )
        assert response.status_code == 200
        assert response.json()["local_time"].startswith("2026-07-27 09:03:00")
