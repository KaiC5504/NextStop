import zipfile
from datetime import date, datetime
from pathlib import Path

import pytest

from nextstop_collector.gtfs.static import (
    GtfsBundle,
    GtfsError,
    absolute_departure,
    active_service_ids,
    feed_url,
    gtfs_seconds,
    mode_for_route_type,
)
from nextstop_collector.timeutil import SYDNEY

CALENDAR = """service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
WD,1,1,1,1,1,0,0,20260101,20261231
WE,0,0,0,0,0,1,1,20260101,20261231
"""

# 27 July 2026 is a Monday. WD is suppressed on the 28th; HOL is added on the 29th.
CALENDAR_DATES = """service_id,date,exception_type
WD,20260728,2
HOL,20260729,1
"""

ROUTES = """route_id,route_short_name,route_long_name,route_type
M1,M1,Metro North West & Bankstown Line,401
T1,T1,North Shore Line,2
"""

TRIPS = """route_id,service_id,trip_id,trip_headsign
M1,WD,trip-morning,Sydenham
M1,WD,trip-after-midnight,Tallawong
M1,HOL,trip-holiday,Sydenham
T1,WD,trip-no-pickup,City
"""

STOPS = """stop_id,stop_name,parent_station
206710,"Chatswood Station",
2067,"Chatswood Station, Platform 1",206710
2068,"Chatswood Station, Platform 2",206710
2000,"Central Station, Platform 16",200060
"""

STOP_TIMES = """trip_id,arrival_time,departure_time,stop_id,stop_sequence,pickup_type,drop_off_type
trip-morning,09:02:30,09:03:00,2067,3,0,0
trip-morning,09:20:00,09:20:30,2000,9,0,0
trip-after-midnight,25:14:30,25:15:00,2067,3,0,0
trip-holiday,10:00:00,10:00:00,2067,3,0,0
trip-no-pickup,09:40:00,09:40:00,2067,3,1,0
"""


@pytest.fixture(scope="module")
def bundle(tmp_path_factory) -> GtfsBundle:
    path = tmp_path_factory.mktemp("gtfs") / "metro.zip"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("calendar.txt", CALENDAR)
        archive.writestr("calendar_dates.txt", CALENDAR_DATES)
        archive.writestr("routes.txt", ROUTES)
        archive.writestr("trips.txt", TRIPS)
        archive.writestr("stops.txt", STOPS)
        archive.writestr("stop_times.txt", STOP_TIMES)
    return GtfsBundle("metro", path)


class TestGtfsSeconds:
    def test_ordinary_time(self):
        assert gtfs_seconds("09:03:00") == 9 * 3600 + 3 * 60

    def test_hours_past_midnight_are_allowed(self):
        assert gtfs_seconds("25:15:00") == 25 * 3600 + 15 * 60

    def test_malformed_returns_none(self):
        assert gtfs_seconds("") is None
        assert gtfs_seconds("nope") is None
        assert gtfs_seconds("09:03") is None


class TestAbsoluteDeparture:
    def test_ordinary_day(self):
        result = absolute_departure(date(2026, 7, 27), gtfs_seconds("09:03:00"))
        assert result.astimezone(SYDNEY).strftime("%Y-%m-%d %H:%M") == "2026-07-27 09:03"

    def test_after_midnight_rolls_to_the_next_calendar_day(self):
        result = absolute_departure(date(2026, 7, 27), gtfs_seconds("25:15:00"))
        assert result.astimezone(SYDNEY).strftime("%Y-%m-%d %H:%M") == "2026-07-28 01:15"

    def test_daylight_saving_end_keeps_the_wall_clock(self):
        """5 April 2026 is when Sydney clocks go back — GTFS days still have 24 hours.

        Anchoring at midnight and adding nine hours would land on 08:03 because the UTC
        offset changes at 03:00. The spec defines its clock as noon minus twelve hours
        precisely to avoid this, which is what the implementation does.
        """
        result = absolute_departure(date(2026, 4, 5), gtfs_seconds("09:03:00"))
        assert result.astimezone(SYDNEY).strftime("%Y-%m-%d %H:%M") == "2026-04-05 09:03"

    def test_daylight_saving_start_keeps_the_wall_clock(self):
        result = absolute_departure(date(2026, 10, 4), gtfs_seconds("09:03:00"))
        assert result.astimezone(SYDNEY).strftime("%Y-%m-%d %H:%M") == "2026-10-04 09:03"


class TestActiveServices:
    def test_weekday_services_run_on_a_monday(self, bundle):
        with zipfile.ZipFile(bundle.path) as archive:
            assert "WD" in active_service_ids(archive, date(2026, 7, 27))

    def test_weekday_services_do_not_run_on_a_saturday(self, bundle):
        with zipfile.ZipFile(bundle.path) as archive:
            active = active_service_ids(archive, date(2026, 8, 1))
        assert "WD" not in active
        assert "WE" in active

    def test_removal_exception_suppresses_a_service(self, bundle):
        with zipfile.ZipFile(bundle.path) as archive:
            assert "WD" not in active_service_ids(archive, date(2026, 7, 28))

    def test_addition_exception_enables_a_service(self, bundle):
        with zipfile.ZipFile(bundle.path) as archive:
            assert "HOL" in active_service_ids(archive, date(2026, 7, 29))


class TestScheduledDepartures:
    def test_returns_departures_for_the_requested_stop_only(self, bundle):
        departures = bundle.scheduled_departures({"2067"}, date(2026, 7, 27))
        assert {d.stop_id for d in departures} == {"2067"}

    def test_excludes_stops_where_boarding_is_not_allowed(self, bundle):
        departures = bundle.scheduled_departures({"2067"}, date(2026, 7, 27))
        assert "trip-no-pickup" not in {d.trip_id for d in departures}

    def test_excludes_services_not_running_that_day(self, bundle):
        departures = bundle.scheduled_departures({"2067"}, date(2026, 7, 27))
        assert "trip-holiday" not in {d.trip_id for d in departures}

    def test_carries_route_name_headsign_and_mode(self, bundle):
        departure = next(
            d
            for d in bundle.scheduled_departures({"2067"}, date(2026, 7, 27))
            if d.trip_id == "trip-morning"
        )
        assert departure.route_name == "M1"
        assert departure.headsign == "Sydenham"
        assert departure.mode == "Metro"
        assert departure.departure.astimezone(SYDNEY).hour == 9


class TestRouteTypeModes:
    def test_tfnsw_extended_metro_type(self):
        assert mode_for_route_type("401") == "Metro"

    def test_plain_rail_and_bus(self):
        assert mode_for_route_type("2") == "Train"
        assert mode_for_route_type("700") == "Bus"

    def test_unlisted_extended_type_falls_back_to_its_hundred(self):
        assert mode_for_route_type("713") == "Bus"
        assert mode_for_route_type("905") == "Light Rail"

    def test_missing_or_junk_is_unknown(self):
        assert mode_for_route_type("") == "Unknown"
        assert mode_for_route_type("banana") == "Unknown"

    def test_results_are_time_ordered(self, bundle):
        departures = bundle.scheduled_departures({"2067", "2000"}, date(2026, 7, 27))
        assert departures == sorted(departures, key=lambda d: d.departure)

    def test_unknown_stop_yields_nothing(self, bundle):
        assert bundle.scheduled_departures({"does-not-exist"}, date(2026, 7, 27)) == []

    def test_empty_stop_set_short_circuits(self, bundle):
        assert bundle.scheduled_departures(set(), date(2026, 7, 27)) == []


class TestFeedVersions:
    def test_metro_is_pinned_to_v2(self):
        """v1/gtfs/schedule/metro answers 200 but expired in Dec 2024 and omits the
        City & Southwest stations, so pinning metro to v2 is load-bearing."""
        from nextstop_collector.config import Settings

        assert Settings().feed_version("metro") == "v2"

    def test_other_feeds_default_to_v1(self):
        from nextstop_collector.config import Settings

        assert Settings().feed_version("sydneytrains") == "v1"

    def test_url_includes_the_version(self):
        assert feed_url("metro", "v2").endswith("/v2/gtfs/schedule/metro")
        assert feed_url("sydneytrains", "v1").endswith("/v1/gtfs/schedule/sydneytrains")


class TestCalendarCoverage:
    def test_reports_the_calendar_span(self, bundle):
        assert bundle.calendar_range() == (date(2026, 1, 1), date(2026, 12, 31))

    def test_covers_a_day_inside_the_span(self, bundle):
        assert bundle.covers(date(2026, 7, 27))

    def test_does_not_cover_a_day_outside_the_span(self, bundle):
        assert not bundle.covers(date(2025, 7, 27))
        assert not bundle.covers(date(2027, 1, 1))

    def test_expired_bundle_yields_no_departures_rather_than_raising(self, bundle):
        """The exact silent-failure mode `covers` exists to surface."""
        assert bundle.scheduled_departures({"2067"}, date(2025, 7, 27)) == []


class TestStopsUnder:
    """The Trip Planner stop ID and GTFS parent_station are the same identifier, which
    makes the join exact instead of a name-similarity guess."""

    def test_returns_the_station_and_its_platforms(self, bundle):
        rows = bundle.stops_under("206710")
        assert {r.stop_id for r in rows} == {"206710", "2067", "2068"}

    def test_does_not_leak_a_different_station(self, bundle):
        assert "2000" not in {r.stop_id for r in bundle.stops_under("206710")}

    def test_unknown_parent_returns_nothing(self, bundle):
        assert bundle.stops_under("999999") == []


class TestStopSearch:
    def test_finds_all_platforms_of_a_station(self, bundle):
        rows = bundle.find_stops("Chatswood")
        assert {r.stop_id for r in rows} == {"206710", "2067", "2068"}

    def test_search_is_case_insensitive(self, bundle):
        assert bundle.find_stops("chatswood")

    def test_missing_bundle_gives_an_actionable_error(self, tmp_path: Path):
        missing = GtfsBundle("metro", tmp_path / "absent.zip")
        with pytest.raises(GtfsError, match="gtfs-refresh"):
            missing.find_stops("Chatswood")
