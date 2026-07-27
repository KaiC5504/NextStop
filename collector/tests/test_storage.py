"""Round-trip tests for the UTC datetime handling.

SQLite has no timestamp type and silently drops tzinfo, which made every read path
return naive datetimes. These pin the fix.
"""

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select
from sqlalchemy.exc import StatementError

from nextstop_collector.storage.db import session_scope
from nextstop_collector.storage.models import Observation
from nextstop_collector.timeutil import SYDNEY, to_sydney


def _store(moment: datetime, corridor: str) -> int:
    with session_scope() as session:
        row = Observation(recorded_at=moment, event="boarded", corridor=corridor)
        session.add(row)
        session.flush()
        return row.id


def _load(row_id: int) -> Observation:
    with session_scope() as session:
        return session.execute(
            select(Observation).where(Observation.id == row_id)
        ).scalar_one()


class TestDatetimeRoundTrip:
    def test_reads_come_back_timezone_aware(self):
        moment = datetime(2026, 7, 27, 9, 3, tzinfo=timezone.utc)
        loaded = _load(_store(moment, "rt-aware"))
        assert loaded.recorded_at.tzinfo is not None
        assert loaded.recorded_at == moment

    def test_sydney_time_survives_as_the_same_instant(self):
        moment = datetime(2026, 7, 27, 9, 3, tzinfo=SYDNEY)
        loaded = _load(_store(moment, "rt-sydney"))
        assert loaded.recorded_at == moment
        assert to_sydney(loaded.recorded_at).hour == 9

    def test_naive_datetimes_are_refused_rather_than_guessed(self):
        # SQLAlchemy wraps the type decorator's ValueError before it reaches the caller.
        with pytest.raises(StatementError) as excinfo:
            _store(datetime(2026, 7, 27, 9, 3), "rt-naive")
        assert isinstance(excinfo.value.orig, ValueError)

    def test_ordering_across_a_dst_boundary_is_preserved(self):
        earlier = datetime(2026, 4, 5, 15, 0, tzinfo=timezone.utc)
        later = earlier + timedelta(hours=2)
        _store(later, "rt-dst")
        _store(earlier, "rt-dst")
        with session_scope() as session:
            rows = session.execute(
                select(Observation)
                .where(Observation.corridor == "rt-dst")
                .order_by(Observation.recorded_at)
            ).scalars().all()
        assert [r.recorded_at for r in rows] == [earlier, later]
