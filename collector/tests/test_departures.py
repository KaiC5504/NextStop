"""Departure parsing and timetable matching.

Payloads are shaped like the v3.3 manual's documented `departure_mon` response. They
are synthetic — replace with a captured response once a key exists.
"""

from datetime import datetime, timedelta, timezone

from nextstop_collector.gtfs.static import ScheduledDeparture
from nextstop_collector.tfnsw.departures import (
    match_scheduled,
    parse_departure_response,
)

PAYLOAD = {
    "stopEvents": [
        {
            "location": {"id": "10101100", "disassembledName": "Chatswood, Platform 1"},
            "departureTimePlanned": "2026-07-27T09:03:00Z",
            "departureTimeEstimated": "2026-07-27T09:07:00Z",
            "transportation": {
                "number": "M1",
                "product": {"class": 2},
                "destination": {"name": "Sydenham"},
            },
        },
        {
            "location": {"id": "10101100", "disassembledName": "Chatswood, Platform 2"},
            "departureTimePlanned": "2026-07-27T09:11:00Z",
            "transportation": {
                "number": "T1",
                "product": {"class": 1},
                "destination": {"name": "City"},
            },
        },
    ]
}


def scheduled(minute: int, route: str = "M1", headsign: str = "Sydenham", trip: str = "t1"):
    return ScheduledDeparture(
        feed="metro",
        trip_id=trip,
        route_id=route,
        route_name=route,
        headsign=headsign,
        stop_id="2067",
        departure=datetime(2026, 7, 27, 9, minute, tzinfo=timezone.utc),
    )


class TestParsing:
    def test_reads_both_events(self):
        assert len(parse_departure_response(PAYLOAD)) == 2

    def test_realtime_delay_is_computed(self):
        event = parse_departure_response(PAYLOAD)[0]
        assert event.api_delay_seconds == 240

    def test_delay_is_none_without_an_estimate(self):
        event = parse_departure_response(PAYLOAD)[1]
        assert event.api_delay_seconds is None
        assert event.effective_departure == event.planned

    def test_mode_comes_from_product_class(self):
        events = parse_departure_response(PAYLOAD)
        assert events[0].mode == "Metro"
        assert events[1].mode == "Train"

    def test_events_are_time_ordered(self):
        events = parse_departure_response(PAYLOAD)
        assert events[0].planned < events[1].planned

    def test_events_without_a_planned_time_are_skipped(self):
        assert parse_departure_response({"stopEvents": [{"transportation": {}}]}) == []

    def test_empty_payload_does_not_raise(self):
        assert parse_departure_response({}) == []


class TestMatching:
    def test_matches_the_departure_at_the_same_minute(self):
        event = parse_departure_response(PAYLOAD)[0]
        match = match_scheduled(event, [scheduled(3), scheduled(11, route="T1", trip="t2")])
        assert match is not None
        assert match.trip_id == "t1"

    def test_no_match_outside_the_tolerance(self):
        event = parse_departure_response(PAYLOAD)[0]
        assert match_scheduled(event, [scheduled(30)]) is None

    def test_small_timetable_drift_still_matches(self):
        event = parse_departure_response(PAYLOAD)[0]
        candidate = scheduled(3)
        drifted = ScheduledDeparture(
            **{**candidate.__dict__, "departure": candidate.departure + timedelta(seconds=45)}
        )
        assert match_scheduled(event, [drifted]) is not None

    def test_route_breaks_a_tie_between_simultaneous_services(self):
        event = parse_departure_response(PAYLOAD)[0]
        wrong_route = scheduled(3, route="T9", headsign="Hornsby", trip="wrong")
        right_route = scheduled(3, route="M1", headsign="Sydenham", trip="right")
        match = match_scheduled(event, [wrong_route, right_route])
        assert match.trip_id == "right"

    def test_matches_even_when_route_naming_differs(self):
        """API route strings and GTFS short names come from different systems."""
        event = parse_departure_response(PAYLOAD)[0]
        differently_named = scheduled(3, route="Metro North West Line", trip="renamed")
        assert match_scheduled(event, [differently_named]).trip_id == "renamed"

    def test_empty_timetable_returns_none(self):
        event = parse_departure_response(PAYLOAD)[0]
        assert match_scheduled(event, []) is None
