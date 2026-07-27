from datetime import datetime

from nextstop_collector.scheduling import (
    OFFPEAK_INTERVAL_SECONDS,
    PEAK_INTERVAL_SECONDS,
    interval_for,
    is_peak,
)
from nextstop_collector.timeutil import SYDNEY


def sydney(year, month, day, hour, minute=0):
    return datetime(year, month, day, hour, minute, tzinfo=SYDNEY)


class TestPeakWindows:
    def test_weekday_morning_is_peak(self):
        assert is_peak(sydney(2026, 7, 27, 8, 30))  # Monday

    def test_weekday_evening_is_peak(self):
        assert is_peak(sydney(2026, 7, 27, 17, 0))

    def test_weekday_midday_is_off_peak(self):
        assert not is_peak(sydney(2026, 7, 27, 12, 0))

    def test_weekend_morning_is_off_peak(self):
        assert not is_peak(sydney(2026, 8, 1, 8, 30))  # Saturday

    def test_window_is_half_open(self):
        assert is_peak(sydney(2026, 7, 27, 7, 0))
        assert not is_peak(sydney(2026, 7, 27, 10, 0))


class TestInterval:
    def test_peak_polls_every_five_minutes(self):
        assert interval_for(sydney(2026, 7, 27, 8, 0)) == PEAK_INTERVAL_SECONDS

    def test_off_peak_polls_hourly(self):
        assert interval_for(sydney(2026, 7, 27, 22, 0)) == OFFPEAK_INTERVAL_SECONDS
