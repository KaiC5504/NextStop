from datetime import date, datetime, timezone
from typing import Any

from sqlalchemy import JSON, Date, DateTime, Float, Index, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.types import TypeDecorator


class UtcDateTime(TypeDecorator):
    """Timezone-aware datetimes that survive a round trip through SQLite.

    SQLite has no native timestamp type and silently drops tzinfo, so reads come back
    naive and blow up anything doing timezone maths. Everything is stored as UTC and
    re-tagged as UTC on the way out; naive values are rejected rather than guessed at.
    """

    impl = DateTime
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError(f"refusing to store naive datetime {value!r}; attach a tzinfo")
        return value.astimezone(timezone.utc)

    def process_result_value(self, value: datetime | None, dialect: Any) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


class Base(DeclarativeBase):
    pass


class ApiCallLog(Base):
    """One row per HTTP attempt, including retries.

    TfNSW exposes no endpoint for checking your own quota consumption, so this table
    is the only record of it. Retries are logged individually because they each draw
    down the quota.
    """

    __tablename__ = "api_call_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    requested_at: Mapped[datetime] = mapped_column(UtcDateTime, index=True)
    quota_date: Mapped[date] = mapped_column(Date, index=True)
    provider: Mapped[str] = mapped_column(String(16))
    endpoint: Mapped[str] = mapped_column(String(64))
    attempt: Mapped[int] = mapped_column(Integer, default=1)
    http_status: Mapped[int | None] = mapped_column(Integer, nullable=True)
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    succeeded: Mapped[bool] = mapped_column(default=False)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)


Index("ix_api_call_provider_day", ApiCallLog.provider, ApiCallLog.quota_date)


class DepartureSample(Base):
    """One upcoming departure as seen at one moment in time.

    The Phase 0 thesis lives in two columns:

    `api_delay_seconds` is estimated minus planned, both from the same Trip Planner
    response. It is always available and never depends on a join, so it is the robust
    headline number.

    `naive_gap_seconds` is estimated minus the *static GTFS* scheduled time. That is
    the gap an app built on the published timetable alone would show wrong, which is
    the claim being tested. It is null when the static match fails, and those failures
    are kept rather than dropped.
    """

    __tablename__ = "departure_sample"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    polled_at: Mapped[datetime] = mapped_column(UtcDateTime, index=True)
    quota_date: Mapped[date] = mapped_column(Date, index=True)

    stop_key: Mapped[str] = mapped_column(String(32), index=True)
    stop_id: Mapped[str] = mapped_column(String(64))
    route: Mapped[str] = mapped_column(String(128), default="")
    destination: Mapped[str] = mapped_column(String(128), default="")
    mode: Mapped[str] = mapped_column(String(32), default="")

    planned_departure: Mapped[datetime] = mapped_column(UtcDateTime, index=True)
    estimated_departure: Mapped[datetime | None] = mapped_column(UtcDateTime, nullable=True)
    scheduled_departure: Mapped[datetime | None] = mapped_column(UtcDateTime, nullable=True)

    api_delay_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    naive_gap_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    # Non-zero means the API's own "planned" disagrees with the published timetable,
    # which is itself worth seeing rather than averaging away.
    planned_vs_scheduled_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)

    matched_static: Mapped[bool] = mapped_column(default=False)
    gtfs_trip_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    gtfs_feed: Mapped[str | None] = mapped_column(String(32), nullable=True)
    raw: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)


Index("ix_sample_stop_planned", DepartureSample.stop_key, DepartureSample.planned_departure)


class TimetableBuild(Base):
    """Records that a feed's timetable for one service day has been parsed into the DB.

    Parsing the 99 MB bus bundle takes about 150 seconds. Keeping the result only in
    memory forced the collector to be a long-running process, because any scheduled
    task would have paid that cost on every single run.
    """

    __tablename__ = "timetable_build"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    feed: Mapped[str] = mapped_column(String(32), index=True)
    service_day: Mapped[date] = mapped_column(Date, index=True)
    built_at: Mapped[datetime] = mapped_column(UtcDateTime)
    entry_count: Mapped[int] = mapped_column(Integer, default=0)

    # Size and mtime of the bundle this was parsed from. A refreshed bundle changes
    # the fingerprint, which invalidates the build rather than serving a stale
    # timetable that looks perfectly valid.
    bundle_fingerprint: Mapped[str] = mapped_column(String(64))
    stop_ids: Mapped[list[str] | None] = mapped_column(JSON, nullable=True)


Index("ix_build_feed_day", TimetableBuild.feed, TimetableBuild.service_day, unique=True)


class TimetableEntry(Base):
    """A timetabled departure, parsed once and reused across processes."""

    __tablename__ = "timetable_entry"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    feed: Mapped[str] = mapped_column(String(32))
    service_day: Mapped[date] = mapped_column(Date)
    stop_id: Mapped[str] = mapped_column(String(64))
    trip_id: Mapped[str] = mapped_column(String(64))
    route_id: Mapped[str] = mapped_column(String(64), default="")
    route_name: Mapped[str] = mapped_column(String(128), default="")
    headsign: Mapped[str] = mapped_column(String(128), default="")
    mode: Mapped[str] = mapped_column(String(32), default="Unknown")
    departure: Mapped[datetime] = mapped_column(UtcDateTime, index=True)


Index("ix_entry_lookup", TimetableEntry.feed, TimetableEntry.service_day, TimetableEntry.stop_id)


class Observation(Base):
    """Ground truth from an iOS Shortcut: what actually happened.

    Optional for the headline result, which TfNSW's own realtime feed supplies. This
    is what shows the realtime estimate was *right*, not merely different.
    """

    __tablename__ = "observation"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    recorded_at: Mapped[datetime] = mapped_column(UtcDateTime, index=True)
    event: Mapped[str] = mapped_column(String(16), index=True)
    corridor: Mapped[str] = mapped_column(String(64), index=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)


class ServiceAlert(Base):
    """Snapshot of a TfNSW service alert, for correlating gaps with published disruption.

    Stored once per revision, not once per poll. The network carries ~276 active alerts
    at any moment and almost none of them change between samples, so writing every one
    every 15 minutes would add ~26,000 near-identical rows a day and hundreds of
    megabytes a week. Keying on the alert's own last-modified stamp keeps the timeline
    of genuine changes and drops the repeats.
    """

    __tablename__ = "service_alert"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    fetched_at: Mapped[datetime] = mapped_column(UtcDateTime, index=True)
    alert_id: Mapped[str] = mapped_column(String(128), index=True)
    last_modified: Mapped[str | None] = mapped_column(String(64), nullable=True)
    priority: Mapped[str | None] = mapped_column(String(32), nullable=True)
    subtitle: Mapped[str | None] = mapped_column(Text, nullable=True)
    content: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)


Index("ix_alert_revision", ServiceAlert.alert_id, ServiceAlert.last_modified)
