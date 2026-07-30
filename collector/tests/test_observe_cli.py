from typer.testing import CliRunner

from nextstop_collector.cli import app
from nextstop_collector.storage.db import session_scope
from nextstop_collector.storage.models import Observation

runner = CliRunner()


def _observations(corridor: str) -> list[Observation]:
    with session_scope() as session:
        rows = session.query(Observation).filter(Observation.corridor == corridor).all()
        # Detach before the session closes so assertions can still read attributes.
        for row in rows:
            session.expunge(row)
        return rows


class TestObserveCommand:
    def test_records_an_observation_now(self):
        result = runner.invoke(app, ["observe", "boarded", "--corridor", "cli-now"])
        assert result.exit_code == 0, result.output
        rows = _observations("cli-now")
        assert len(rows) == 1
        assert rows[0].event == "boarded"

    def test_accepts_a_sydney_local_time(self):
        result = runner.invoke(
            app,
            ["observe", "arrived", "--corridor", "cli-at", "--at", "2026-07-28 09:03"],
        )
        assert result.exit_code == 0, result.output
        rows = _observations("cli-at")
        assert len(rows) == 1
        # 09:03 Sydney in July is UTC+10, so 23:03 the previous day in UTC.
        assert rows[0].recorded_at.hour == 23
        assert rows[0].recorded_at.day == 27

    def test_rejects_an_unknown_event(self):
        result = runner.invoke(app, ["observe", "teleported", "--corridor", "cli-bad"])
        assert result.exit_code != 0

    def test_rejects_an_unparseable_time(self):
        result = runner.invoke(
            app, ["observe", "boarded", "--corridor", "cli-bad2", "--at", "yesterday-ish"]
        )
        assert result.exit_code != 0
