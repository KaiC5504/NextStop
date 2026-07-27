"""Persisted timetables.

Parsing the bus bundle takes about 150 seconds. Holding that only in memory is what
forced the collector to be a long-running process — any scheduled task would have paid
the cost on every run. Parsing once per service day into SQLite means a fresh process
starts in about a second, so cron, systemd timers or Task Scheduler all work, and a
reboot costs nothing.
"""

import logging
from datetime import date, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .gtfs.static import GtfsBundle, ScheduledDeparture
from .storage.db import session_scope
from .storage.models import TimetableBuild, TimetableEntry
from .timeutil import now_utc

log = logging.getLogger(__name__)

RETENTION_DAYS = 30


def bundle_fingerprint(bundle: GtfsBundle) -> str:
    """Changes whenever the bundle is re-downloaded, invalidating anything built from it."""
    if not bundle.exists():
        return "missing"
    stat = bundle.path.stat()
    return f"{stat.st_size}:{int(stat.st_mtime)}"


def _existing_build(
    session: Session, feed: str, service_day: date
) -> TimetableBuild | None:
    return session.execute(
        select(TimetableBuild).where(
            TimetableBuild.feed == feed, TimetableBuild.service_day == service_day
        )
    ).scalar_one_or_none()


def is_built(feed: str, service_day: date, fingerprint: str, stop_ids: set[str]) -> bool:
    with session_scope() as session:
        build = _existing_build(session, feed, service_day)
        if build is None or build.bundle_fingerprint != fingerprint:
            return False
        # A build only counts if it covers everything being asked for; adding a stop to
        # the watchlist must not silently return a timetable that omits it.
        return stop_ids.issubset(set(build.stop_ids or []))


def build(
    bundle: GtfsBundle, service_day: date, stop_ids: set[str], fingerprint: str
) -> int:
    departures = bundle.scheduled_departures(stop_ids, service_day)

    with session_scope() as session:
        session.execute(
            delete(TimetableEntry).where(
                TimetableEntry.feed == bundle.feed,
                TimetableEntry.service_day == service_day,
            )
        )
        existing = _existing_build(session, bundle.feed, service_day)
        if existing is not None:
            session.delete(existing)
        session.flush()

        session.add_all(
            TimetableEntry(
                feed=bundle.feed,
                service_day=service_day,
                stop_id=d.stop_id,
                trip_id=d.trip_id,
                route_id=d.route_id,
                route_name=d.route_name,
                headsign=d.headsign,
                mode=d.mode,
                departure=d.departure,
            )
            for d in departures
        )
        session.add(
            TimetableBuild(
                feed=bundle.feed,
                service_day=service_day,
                built_at=now_utc(),
                entry_count=len(departures),
                bundle_fingerprint=fingerprint,
                stop_ids=sorted(stop_ids),
            )
        )
    log.info(
        "built %s timetable for %s: %d departures", bundle.feed, service_day, len(departures)
    )
    return len(departures)


def ensure_built(bundle: GtfsBundle, service_day: date, stop_ids: set[str]) -> bool:
    """Parse and store this feed's timetable for a day if not already done.

    Returns True when a parse actually happened, which is the slow path.
    """
    if not stop_ids or not bundle.exists():
        return False
    fingerprint = bundle_fingerprint(bundle)
    if is_built(bundle.feed, service_day, fingerprint, stop_ids):
        return False
    build(bundle, service_day, stop_ids, fingerprint)
    return True


def scheduled_for(feed: str, stop_ids: set[str], service_day: date) -> list[ScheduledDeparture]:
    if not stop_ids:
        return []
    with session_scope() as session:
        rows = session.execute(
            select(TimetableEntry)
            .where(
                TimetableEntry.feed == feed,
                TimetableEntry.service_day == service_day,
                TimetableEntry.stop_id.in_(sorted(stop_ids)),
            )
            .order_by(TimetableEntry.departure)
        ).scalars()
        return [
            ScheduledDeparture(
                feed=row.feed,
                trip_id=row.trip_id,
                route_id=row.route_id,
                route_name=row.route_name,
                headsign=row.headsign,
                stop_id=row.stop_id,
                departure=row.departure,
                mode=row.mode,
            )
            for row in rows
        ]


def prune(before: date | None = None) -> int:
    """Drop timetables for service days well in the past."""
    cutoff = before or (now_utc().date() - timedelta(days=RETENTION_DAYS))
    with session_scope() as session:
        removed = session.execute(
            delete(TimetableEntry).where(TimetableEntry.service_day < cutoff)
        ).rowcount
        session.execute(delete(TimetableBuild).where(TimetableBuild.service_day < cutoff))
    return removed or 0


def status() -> list[tuple[str, date, int, datetime]]:
    with session_scope() as session:
        rows = session.execute(
            select(
                TimetableBuild.feed,
                TimetableBuild.service_day,
                TimetableBuild.entry_count,
                TimetableBuild.built_at,
            ).order_by(TimetableBuild.service_day.desc(), TimetableBuild.feed)
        ).all()
        return [tuple(r) for r in rows]
