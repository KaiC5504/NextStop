from datetime import date, datetime, timezone
from typing import Any

from sqlalchemy import JSON, Date, DateTime, Float, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
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


class TripQuery(Base):
    """A single trip-planning request to one provider, with its response kept verbatim.

    The raw payload is stored so the normalisation logic can be rewritten and replayed
    against collected data instead of re-collecting another week of commutes.
    """

    __tablename__ = "trip_query"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    requested_at: Mapped[datetime] = mapped_column(UtcDateTime, index=True)
    quota_date: Mapped[date] = mapped_column(Date, index=True)
    provider: Mapped[str] = mapped_column(String(16), index=True)
    corridor: Mapped[str] = mapped_column(String(64), index=True)
    origin_ref: Mapped[str] = mapped_column(String(64))
    destination_ref: Mapped[str] = mapped_column(String(64))
    depart_after: Mapped[datetime] = mapped_column(UtcDateTime)
    http_status: Mapped[int | None] = mapped_column(Integer, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw_response: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)

    options: Mapped[list["TripOption"]] = relationship(
        back_populates="query", cascade="all, delete-orphan"
    )


class TripOption(Base):
    """One suggested journey from a TripQuery, flattened for comparison."""

    __tablename__ = "trip_option"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    query_id: Mapped[int] = mapped_column(ForeignKey("trip_query.id"), index=True)
    rank: Mapped[int] = mapped_column(Integer)
    departure_time: Mapped[datetime | None] = mapped_column(UtcDateTime, nullable=True)
    arrival_time: Mapped[datetime | None] = mapped_column(UtcDateTime, nullable=True)
    duration_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)

    # True when the provider supplied a live estimate rather than only timetable data.
    is_realtime: Mapped[bool] = mapped_column(default=False)

    # Timetabled departure, kept alongside the realtime one so delay is recoverable.
    departure_planned: Mapped[datetime | None] = mapped_column(UtcDateTime, nullable=True)
    mode_sequence: Mapped[str] = mapped_column(String(256), default="")
    leg_count: Mapped[int] = mapped_column(Integer, default=0)
    legs: Mapped[list[dict[str, Any]] | None] = mapped_column(JSON, nullable=True)

    query: Mapped[TripQuery] = relationship(back_populates="options")


class Observation(Base):
    """Ground truth: what actually happened, sent from an iOS Shortcut.

    Without this the dataset can only show that the two providers disagree, not which
    one was right.
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
    """Snapshot of a TfNSW service alert, for scoring disruption handling."""

    __tablename__ = "service_alert"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    fetched_at: Mapped[datetime] = mapped_column(UtcDateTime, index=True)
    alert_id: Mapped[str] = mapped_column(String(128), index=True)
    priority: Mapped[str | None] = mapped_column(String(32), nullable=True)
    subtitle: Mapped[str | None] = mapped_column(Text, nullable=True)
    content: Mapped[str | None] = mapped_column(Text, nullable=True)
    raw: Mapped[dict[str, Any] | None] = mapped_column(JSON, nullable=True)
