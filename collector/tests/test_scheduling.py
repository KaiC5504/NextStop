from datetime import datetime

from nextstop_collector.collect import service_days_for
from nextstop_collector.scheduling import (
    BASELINE_INTERVAL_SECONDS,
    COMMUTE_INTERVAL_SECONDS,
    in_commute_window,
    interval_for,
)
from nextstop_collector.timeutil import SYDNEY


def sydney(year, month, day, hour, minute=0):
    return datetime(year, month, day, hour, minute, tzinfo=SYDNEY)


class TestCommuteWindow:
    def test_weekday_morning_is_in_window(self):
        assert in_commute_window(sydney(2026, 7, 27, 8, 30))  # Monday

    def test_weekday_evening_is_in_window(self):
        assert in_commute_window(sydney(2026, 7, 27, 17, 0))

    def test_weekday_midday_is_outside(self):
        assert not in_commute_window(sydney(2026, 7, 27, 12, 0))

    def test_weekend_is_outside(self):
        assert not in_commute_window(sydney(2026, 8, 1, 8, 30))  # Saturday

    def test_window_is_half_open(self):
        assert in_commute_window(sydney(2026, 7, 27, 6, 0))
        assert not in_commute_window(sydney(2026, 7, 27, 10, 0))


class TestInterval:
    def test_commute_window_samples_every_fifteen_minutes(self):
        assert interval_for(sydney(2026, 7, 27, 8, 0)) == COMMUTE_INTERVAL_SECONDS
        assert COMMUTE_INTERVAL_SECONDS == 15 * 60

    def test_outside_the_window_falls_back_to_hourly(self):
        assert interval_for(sydney(2026, 7, 27, 22, 0)) == BASELINE_INTERVAL_SECONDS


class TestServiceDays:
    def test_includes_yesterday_for_after_midnight_services(self):
        """A 00:20 departure is 24:20 on the previous service day in GTFS."""
        days = service_days_for(sydney(2026, 7, 28, 0, 20))
        assert days[-1].isoformat() == "2026-07-28"
        assert days[0].isoformat() == "2026-07-27"
