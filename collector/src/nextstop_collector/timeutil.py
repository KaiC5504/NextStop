"""Time handling for the collector.

Every schedule decision and quota boundary is computed in Sydney time regardless of
where the process runs, so moving the collector between a Windows box and a VPS in
another region cannot silently shift the polling windows or the quota day.
"""

from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

SYDNEY = ZoneInfo("Australia/Sydney")


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def now_sydney() -> datetime:
    return datetime.now(SYDNEY)


def to_sydney(moment: datetime) -> datetime:
    if moment.tzinfo is None:
        raise ValueError("refusing to localise a naive datetime; attach a tzinfo first")
    return moment.astimezone(SYDNEY)


def quota_day(moment: datetime, reset_tz: str = "Australia/Sydney") -> date:
    """The calendar date a call counts against for TfNSW daily quota purposes."""
    return moment.astimezone(ZoneInfo(reset_tz)).date()


def quota_day_bounds(day: date, reset_tz: str = "Australia/Sydney") -> tuple[datetime, datetime]:
    """UTC half-open interval [start, end) covering a quota day."""
    tz = ZoneInfo(reset_tz)
    start = datetime.combine(day, datetime.min.time(), tzinfo=tz)
    end = start + timedelta(days=1)
    return start.astimezone(timezone.utc), end.astimezone(timezone.utc)


def parse_api_datetime(raw: str | None) -> datetime | None:
    """Parse the ISO-8601 UTC timestamps the Trip Planner returns (e.g. 2026-07-27T09:03:00Z)."""
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
