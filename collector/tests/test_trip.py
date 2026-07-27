"""Normalisation tests against payloads shaped like the v3.3 manual's documented response.

These fixtures are synthetic. Once a real API key exists, capture an actual response with
`nextstop collect-once --raw` and replace them — the field names here are from the manual,
not from observed traffic.
"""

from datetime import datetime, timezone

from nextstop_collector.tfnsw.trip import parse_trip_response

REALTIME_PAYLOAD = {
    "journeys": [
        {
            "legs": [
                {
                    "duration": 300,
                    "origin": {
                        "name": "Chatswood Station, Platform 1",
                        "disassembledName": "Chatswood",
                        "departureTimePlanned": "2026-07-27T09:03:00Z",
                        "departureTimeEstimated": "2026-07-27T09:05:00Z",
                    },
                    "destination": {
                        "disassembledName": "Martin Place",
                        "arrivalTimePlanned": "2026-07-27T09:18:00Z",
                        "arrivalTimeEstimated": "2026-07-27T09:20:00Z",
                    },
                    "transportation": {"product": {"class": 2}, "number": "Metro"},
                },
                {
                    "duration": 420,
                    "origin": {
                        "disassembledName": "Martin Place",
                        "departureTimePlanned": "2026-07-27T09:22:00Z",
                    },
                    "destination": {
                        "disassembledName": "University of Sydney",
                        "arrivalTimePlanned": "2026-07-27T09:35:00Z",
                    },
                    "transportation": {"product": {"class": 5}, "number": "412"},
                },
            ]
        }
    ]
}

TIMETABLE_ONLY_PAYLOAD = {
    "journeys": [
        {
            "legs": [
                {
                    "duration": 900,
                    "origin": {
                        "disassembledName": "Chatswood",
                        "departureTimePlanned": "2026-07-27T09:03:00Z",
                    },
                    "destination": {
                        "disassembledName": "Central",
                        "arrivalTimePlanned": "2026-07-27T09:25:00Z",
                    },
                    "transportation": {"product": {"class": 1}, "number": "T1"},
                }
            ]
        }
    ]
}


class TestParseTripResponse:
    def test_modes_are_named_from_product_class(self):
        journey = parse_trip_response(REALTIME_PAYLOAD)[0]
        assert journey.mode_sequence == "Metro -> Bus"

    def test_realtime_estimate_wins_over_timetable(self):
        journey = parse_trip_response(REALTIME_PAYLOAD)[0]
        assert journey.is_realtime
        assert journey.departure_time == datetime(2026, 7, 27, 9, 5, tzinfo=timezone.utc)
        assert journey.departure_planned == datetime(2026, 7, 27, 9, 3, tzinfo=timezone.utc)

    def test_arrival_comes_from_the_final_leg(self):
        journey = parse_trip_response(REALTIME_PAYLOAD)[0]
        assert journey.arrival_time == datetime(2026, 7, 27, 9, 35, tzinfo=timezone.utc)

    def test_duration_spans_first_departure_to_last_arrival(self):
        journey = parse_trip_response(REALTIME_PAYLOAD)[0]
        assert journey.duration_seconds == 30 * 60

    def test_timetable_only_journey_is_not_flagged_realtime(self):
        journey = parse_trip_response(TIMETABLE_ONLY_PAYLOAD)[0]
        assert not journey.is_realtime
        assert journey.departure_time == journey.departure_planned

    def test_empty_and_malformed_payloads_do_not_raise(self):
        assert parse_trip_response({}) == []
        assert parse_trip_response({"journeys": []}) == []
        assert parse_trip_response({"journeys": [{"legs": []}]}) == []

    def test_unknown_product_class_is_labelled_not_dropped(self):
        payload = {
            "journeys": [
                {
                    "legs": [
                        {
                            "origin": {"departureTimePlanned": "2026-07-27T09:03:00Z"},
                            "destination": {"arrivalTimePlanned": "2026-07-27T09:10:00Z"},
                            "transportation": {"product": {"class": 42}},
                        }
                    ]
                }
            ]
        }
        assert parse_trip_response(payload)[0].mode_sequence == "Class 42"
