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


BUS_PAYLOAD = {
    "stopEvents": [
        {
            "location": {"id": "206710", "disassembledName": "Chatswood, Stand D"},
            "departureTimePlanned": "2026-07-27T09:03:00Z",
            "departureTimeEstimated": "2026-07-27T09:09:00Z",
            "transportation": {
                "number": "257",
                "product": {"class": 5},
                "destination": {"name": "Balmoral"},
            },
        }
    ]
}


def scheduled(
    minute: int,
    route: str = "M1",
    headsign: str = "Sydenham",
    trip: str = "t1",
    mode: str = "Metro",
):
    return ScheduledDeparture(
        feed="metro",
        trip_id=trip,
        route_id=route,
        route_name=route,
        headsign=headsign,
        stop_id="2067",
        departure=datetime(2026, 7, 27, 9, minute, tzinfo=timezone.utc),
        mode=mode,
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


class TestModeIsAHardFilter:
    """Interchanges put a bus stand metres from the platforms.

    Without a mode filter a bus leaving at 09:03 matches a train timetabled for 09:03
    and fabricates a delay. This was observed live at Chatswood, where 8 of 40 sampled
    bus departures falsely matched rail services.
    """

    def test_bus_does_not_match_a_simultaneous_train(self):
        bus = parse_departure_response(BUS_PAYLOAD)[0]
        assert bus.mode == "Bus"
        assert match_scheduled(bus, [scheduled(3, mode="Train")]) is None

    def test_bus_does_not_match_a_simultaneous_metro(self):
        bus = parse_departure_response(BUS_PAYLOAD)[0]
        assert match_scheduled(bus, [scheduled(3, mode="Metro")]) is None

    def test_bus_matches_a_bus(self):
        bus = parse_departure_response(BUS_PAYLOAD)[0]
        match = match_scheduled(bus, [scheduled(3, route="257", mode="Bus", trip="b1")])
        assert match is not None and match.trip_id == "b1"

    def test_school_bus_and_bus_are_interchangeable(self):
        bus = parse_departure_response(BUS_PAYLOAD)[0]
        assert match_scheduled(bus, [scheduled(3, mode="School Bus", trip="sb")]) is not None

    def test_unknown_mode_never_matches(self):
        """A missing label is not evidence of a match."""
        event = parse_departure_response(PAYLOAD)[0]
        assert match_scheduled(event, [scheduled(3, mode="Unknown")]) is None

    def test_correct_mode_still_wins_over_a_closer_wrong_mode(self):
        event = parse_departure_response(PAYLOAD)[0]
        near_wrong = scheduled(3, mode="Bus", trip="wrong")
        exact_right = scheduled(3, mode="Metro", trip="right")
        assert match_scheduled(event, [near_wrong, exact_right]).trip_id == "right"
