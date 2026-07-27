from datetime import date, datetime, timezone

import pytest

from nextstop_collector.timeutil import parse_api_datetime, quota_day, quota_day_bounds, to_sydney


class TestQuotaDay:
    def test_late_utc_evening_is_still_the_same_sydney_day(self):
        moment = datetime(2026, 7, 27, 13, 0, tzinfo=timezone.utc)  # 23:00 Sydney
        assert quota_day(moment) == date(2026, 7, 27)

    def test_crossing_sydney_midnight_rolls_the_quota_day(self):
        moment = datetime(2026, 7, 27, 14, 30, tzinfo=timezone.utc)  # 00:30 next day Sydney
        assert quota_day(moment) == date(2026, 7, 28)

    def test_daylight_saving_makes_the_two_readings_differ(self):
        """In January Sydney is UTC+11, so 'midnight AEST' and Sydney midnight disagree.

        This is the ambiguity documented in Settings.quota_reset_tz — pinning it here so
        a future change to the default is a deliberate one.
        """
        moment = datetime(2026, 1, 15, 13, 30, tzinfo=timezone.utc)
        assert quota_day(moment, "Australia/Sydney") == date(2026, 1, 16)
        assert quota_day(moment, "Etc/GMT-10") == date(2026, 1, 15)

    def test_bounds_span_exactly_one_day(self):
        start, end = quota_day_bounds(date(2026, 7, 27))
        assert (end - start).total_seconds() == 24 * 3600
        assert quota_day(start) == date(2026, 7, 27)


class TestToSydney:
    def test_naive_datetime_is_rejected(self):
        with pytest.raises(ValueError):
            to_sydney(datetime(2026, 7, 27, 9, 0))

    def test_converts_to_local_wall_clock(self):
        moment = datetime(2026, 7, 26, 23, 3, tzinfo=timezone.utc)
        assert to_sydney(moment).strftime("%Y%m%d %H%M") == "20260727 0903"


class TestParseApiDatetime:
    def test_parses_zulu_timestamps(self):
        parsed = parse_api_datetime("2026-07-27T09:03:00Z")
        assert parsed == datetime(2026, 7, 27, 9, 3, tzinfo=timezone.utc)

    def test_empty_and_malformed_return_none(self):
        assert parse_api_datetime("") is None
        assert parse_api_datetime(None) is None
        assert parse_api_datetime("not a date") is None
