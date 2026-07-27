"""Persisted timetable behaviour.

The point of this layer is that a fresh process does not re-parse a 99 MB bundle, so
the tests that matter are about when a stored build is trusted and when it is thrown
away.
"""

import zipfile
from datetime import date

import pytest

from nextstop_collector import timetable
from nextstop_collector.gtfs.static import GtfsBundle

CALENDAR = """service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
WD,1,1,1,1,1,0,0,20260101,20261231
"""
ROUTES = """route_id,route_short_name,route_long_name,route_type
M1,M1,Metro,401
"""
TRIPS = """route_id,service_id,trip_id,trip_headsign
M1,WD,trip-a,Sydenham
M1,WD,trip-b,Sydenham
"""
STOPS = """stop_id,stop_name,parent_station
9001,"Test Station, Platform 1",900010
9002,"Test Station, Platform 2",900010
"""
STOP_TIMES = """trip_id,arrival_time,departure_time,stop_id,stop_sequence,pickup_type,drop_off_type
trip-a,09:02:30,09:03:00,9001,3,0,0
trip-b,09:12:30,09:13:00,9002,3,0,0
"""

DAY = date(2026, 7, 27)


def write_bundle(path, stop_times=STOP_TIMES):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("calendar.txt", CALENDAR)
        archive.writestr("routes.txt", ROUTES)
        archive.writestr("trips.txt", TRIPS)
        archive.writestr("stops.txt", STOPS)
        archive.writestr("stop_times.txt", stop_times)


@pytest.fixture
def bundle(tmp_path, request):
    # A distinct feed name per test keeps stored builds from colliding in the shared
    # test database.
    path = tmp_path / "feed.zip"
    write_bundle(path)
    return GtfsBundle(f"test-{request.node.name[:24]}", path)


class TestEnsureBuilt:
    def test_first_call_parses_and_stores(self, bundle):
        assert timetable.ensure_built(bundle, DAY, {"9001", "9002"}) is True
        stored = timetable.scheduled_for(bundle.feed, {"9001", "9002"}, DAY)
        assert {d.trip_id for d in stored} == {"trip-a", "trip-b"}

    def test_second_call_is_a_no_op(self, bundle):
        timetable.ensure_built(bundle, DAY, {"9001", "9002"})
        assert timetable.ensure_built(bundle, DAY, {"9001", "9002"}) is False

    def test_stored_entries_keep_route_headsign_and_mode(self, bundle):
        timetable.ensure_built(bundle, DAY, {"9001"})
        entry = timetable.scheduled_for(bundle.feed, {"9001"}, DAY)[0]
        assert entry.route_name == "M1"
        assert entry.headsign == "Sydenham"
        assert entry.mode == "Metro"
        assert entry.feed == bundle.feed

    def test_only_requested_stops_come_back(self, bundle):
        timetable.ensure_built(bundle, DAY, {"9001", "9002"})
        stored = timetable.scheduled_for(bundle.feed, {"9001"}, DAY)
        assert {d.stop_id for d in stored} == {"9001"}

    def test_empty_stop_set_does_nothing(self, bundle):
        assert timetable.ensure_built(bundle, DAY, set()) is False


class TestInvalidation:
    def test_a_refreshed_bundle_forces_a_rebuild(self, bundle):
        """A new download must not be served from a build made against the old file."""
        timetable.ensure_built(bundle, DAY, {"9001", "9002"})
        write_bundle(
            bundle.path,
            stop_times=(
                "trip_id,arrival_time,departure_time,stop_id,stop_sequence,pickup_type,drop_off_type\n"
                "trip-a,09:31:30,09:32:00,9001,3,0,0\n"
            ),
        )
        assert timetable.ensure_built(bundle, DAY, {"9001", "9002"}) is True
        stored = timetable.scheduled_for(bundle.feed, {"9001"}, DAY)
        assert len(stored) == 1
        assert stored[0].departure.minute == 32

    def test_widening_the_stop_set_forces_a_rebuild(self, bundle):
        """Adding a stop to the watchlist must not return a timetable that omits it."""
        timetable.ensure_built(bundle, DAY, {"9001"})
        assert timetable.ensure_built(bundle, DAY, {"9001", "9002"}) is True
        assert len(timetable.scheduled_for(bundle.feed, {"9001", "9002"}, DAY)) == 2

    def test_a_different_service_day_is_built_separately(self, bundle):
        timetable.ensure_built(bundle, DAY, {"9001"})
        assert timetable.scheduled_for(bundle.feed, {"9001"}, date(2026, 7, 28)) == []


class TestPrune:
    def test_drops_days_before_the_cutoff_only(self, bundle):
        timetable.ensure_built(bundle, DAY, {"9001", "9002"})
        timetable.prune(before=date(2026, 7, 20))
        assert timetable.scheduled_for(bundle.feed, {"9001"}, DAY)

        timetable.prune(before=date(2026, 8, 1))
        assert timetable.scheduled_for(bundle.feed, {"9001"}, DAY) == []
