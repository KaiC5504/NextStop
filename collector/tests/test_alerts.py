"""Service alert storage.

The network carries a few hundred active alerts at any moment and almost none change
between polls, so the thing worth testing is that repeats are dropped while genuine
revisions are kept.
"""

from datetime import datetime, timezone

from sqlalchemy import select

from nextstop_collector.collect import collect_service_alerts
from nextstop_collector.storage.db import session_scope
from nextstop_collector.storage.models import ServiceAlert
from nextstop_collector.tfnsw.trip import parse_service_alerts


def payload(alert_id: str, modified: str, subtitle: str = "Trackwork"):
    return {
        "infos": {
            "current": [
                {
                    "id": alert_id,
                    "subtitle": subtitle,
                    "priority": "high",
                    "content": "Buses replace trains",
                    "timestamps": {"lastModification": modified},
                    "affected": {"lines": [{"id": "T1"}], "stops": [{"id": "206710"}]},
                }
            ]
        }
    }


class FakeClient:
    def __init__(self, response):
        self.response = response

    def service_alerts(self, when, stop_id=None):
        return self.response


def stored_for(alert_id: str) -> list[ServiceAlert]:
    with session_scope() as session:
        return list(
            session.execute(
                select(ServiceAlert).where(ServiceAlert.alert_id == alert_id)
            ).scalars()
        )


NOW = datetime(2026, 7, 28, 9, 0, tzinfo=timezone.utc)


class TestParsing:
    def test_extracts_the_fields_worth_keeping(self):
        alert = parse_service_alerts(payload("a1", "2026-07-28T08:00:00Z"))[0]
        assert alert["alert_id"] == "a1"
        assert alert["last_modified"] == "2026-07-28T08:00:00Z"
        assert alert["affected_lines"] == 1
        assert alert["affected_stops"] == 1

    def test_empty_payload_is_fine(self):
        assert parse_service_alerts({}) == []


class TestDeduplication:
    def test_first_sighting_is_stored(self):
        assert collect_service_alerts(FakeClient(payload("dedup-1", "M1")), NOW) == 1
        assert len(stored_for("dedup-1")) == 1

    def test_unchanged_alert_is_not_stored_again(self):
        client = FakeClient(payload("dedup-2", "M1"))
        collect_service_alerts(client, NOW)
        assert collect_service_alerts(client, NOW) == 0
        assert collect_service_alerts(client, NOW) == 0
        assert len(stored_for("dedup-2")) == 1

    def test_a_revised_alert_is_stored_as_a_new_row(self):
        collect_service_alerts(FakeClient(payload("dedup-3", "M1")), NOW)
        assert collect_service_alerts(FakeClient(payload("dedup-3", "M2")), NOW) == 1
        rows = stored_for("dedup-3")
        assert len(rows) == 2
        assert {r.last_modified for r in rows} == {"M1", "M2"}

    def test_distinct_alerts_are_all_kept(self):
        collect_service_alerts(FakeClient(payload("dedup-4a", "M1")), NOW)
        collect_service_alerts(FakeClient(payload("dedup-4b", "M1")), NOW)
        assert stored_for("dedup-4a") and stored_for("dedup-4b")
