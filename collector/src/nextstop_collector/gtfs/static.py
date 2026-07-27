"""Static GTFS bundles: what a naive timetable consumer would show.

This is the baseline half of Phase 0. The published schedule says a service leaves at
09:03; the Trip Planner's realtime estimate says it actually leaves at 09:07. That
delta is the whole thesis, and it needs an independent source for the scheduled side —
taking both numbers from the same API response would be circular.

Bundles are large, so `stop_times.txt` is streamed and filtered rather than loaded.
"""

import csv
import io
import logging
import time
import zipfile
from dataclasses import dataclass
from datetime import date, datetime, time as time_of_day, timedelta
from pathlib import Path

import httpx

from ..config import Settings, get_settings
from ..storage.db import session_scope
from ..storage.models import ApiCallLog
from ..timeutil import SYDNEY, now_utc, quota_day

BASE_URL = "https://api.transport.nsw.gov.au/v1/gtfs/schedule/"
PROVIDER = "tfnsw"

# GTFS pickup_type / drop_off_type: 1 means the service does not pick up / set down.
_NOT_AVAILABLE = "1"

log = logging.getLogger(__name__)


class GtfsError(RuntimeError):
    pass


@dataclass(frozen=True)
class StopRow:
    stop_id: str
    stop_name: str
    parent_station: str


@dataclass(frozen=True)
class ScheduledDeparture:
    feed: str
    trip_id: str
    route_id: str
    route_name: str
    headsign: str
    stop_id: str
    departure: datetime


def gtfs_seconds(value: str) -> int | None:
    """Parse a GTFS time. Hours may exceed 24 for services running past midnight."""
    parts = value.strip().split(":")
    if len(parts) != 3:
        return None
    try:
        hours, minutes, seconds = (int(p) for p in parts)
    except ValueError:
        return None
    return hours * 3600 + minutes * 60 + seconds


def absolute_departure(service_day: date, seconds: int) -> datetime:
    """Turn a GTFS time-of-day into a real instant on a service date.

    GTFS defines its clock as "noon minus 12 hours" on the service date precisely so
    that days containing a daylight-saving transition still have 24 nominal hours.
    Anchoring at midday and offsetting reproduces that; anchoring at midnight would
    shift every departure by an hour on the two transition days each year.
    """
    midday = datetime.combine(service_day, time_of_day(12), tzinfo=SYDNEY)
    return midday + timedelta(seconds=seconds - 12 * 3600)


def _read_csv(archive: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    if name not in archive.namelist():
        return []
    with archive.open(name) as handle:
        return list(csv.DictReader(io.TextIOWrapper(handle, encoding="utf-8-sig")))


def _stream_csv(archive: zipfile.ZipFile, name: str):
    if name not in archive.namelist():
        return
    with archive.open(name) as handle:
        yield from csv.DictReader(io.TextIOWrapper(handle, encoding="utf-8-sig"))


def active_service_ids(archive: zipfile.ZipFile, service_day: date) -> set[str]:
    """Service IDs running on a given date, applying calendar_dates exceptions."""
    stamp = service_day.strftime("%Y%m%d")
    weekday = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")[
        service_day.weekday()
    ]

    active: set[str] = set()
    for row in _read_csv(archive, "calendar.txt"):
        if row.get(weekday) != "1":
            continue
        if not (row.get("start_date", "") <= stamp <= row.get("end_date", "")):
            continue
        active.add(row["service_id"])

    # Some TfNSW feeds ship only calendar_dates.txt, so these exceptions are not
    # merely edge cases — they can be the entire schedule.
    for row in _read_csv(archive, "calendar_dates.txt"):
        if row.get("date") != stamp:
            continue
        if row.get("exception_type") == "1":
            active.add(row["service_id"])
        elif row.get("exception_type") == "2":
            active.discard(row["service_id"])

    return active


class GtfsBundle:
    def __init__(self, feed: str, path: Path) -> None:
        self.feed = feed
        self.path = path

    def exists(self) -> bool:
        return self.path.exists()

    def age_hours(self) -> float:
        if not self.exists():
            return float("inf")
        return (time.time() - self.path.stat().st_mtime) / 3600

    def _open(self) -> zipfile.ZipFile:
        if not self.exists():
            raise GtfsError(
                f"no cached bundle for {self.feed!r}. Run `nextstop gtfs-refresh` first."
            )
        return zipfile.ZipFile(self.path)

    def find_stops(self, fragment: str) -> list[StopRow]:
        needle = fragment.casefold()
        with self._open() as archive:
            return [
                StopRow(
                    stop_id=row.get("stop_id", ""),
                    stop_name=row.get("stop_name", ""),
                    parent_station=row.get("parent_station", ""),
                )
                for row in _stream_csv(archive, "stops.txt")
                if needle in row.get("stop_name", "").casefold()
            ]

    def scheduled_departures(
        self, stop_ids: set[str], service_day: date
    ) -> list[ScheduledDeparture]:
        if not stop_ids:
            return []

        with self._open() as archive:
            services = active_service_ids(archive, service_day)
            routes = {
                row["route_id"]: row.get("route_short_name") or row.get("route_long_name") or ""
                for row in _read_csv(archive, "routes.txt")
            }
            trips = {
                row["trip_id"]: (row.get("route_id", ""), row.get("trip_headsign", ""))
                for row in _stream_csv(archive, "trips.txt")
                if row.get("service_id") in services
            }

            departures: list[ScheduledDeparture] = []
            for row in _stream_csv(archive, "stop_times.txt"):
                if row.get("stop_id") not in stop_ids:
                    continue
                trip = trips.get(row.get("trip_id", ""))
                if trip is None:
                    continue
                if row.get("pickup_type") == _NOT_AVAILABLE:
                    continue
                seconds = gtfs_seconds(row.get("departure_time") or "")
                if seconds is None:
                    continue

                route_id, headsign = trip
                departures.append(
                    ScheduledDeparture(
                        feed=self.feed,
                        trip_id=row["trip_id"],
                        route_id=route_id,
                        route_name=routes.get(route_id, ""),
                        headsign=headsign,
                        stop_id=row["stop_id"],
                        departure=absolute_departure(service_day, seconds),
                    )
                )

        departures.sort(key=lambda d: d.departure)
        return departures


def bundle_for(feed: str, settings: Settings | None = None) -> GtfsBundle:
    settings = settings or get_settings()
    return GtfsBundle(feed, settings.gtfs_cache_dir / f"{feed}.zip")


def download_bundle(feed: str, settings: Settings | None = None) -> GtfsBundle:
    settings = settings or get_settings()
    bundle = bundle_for(feed, settings)
    bundle.path.parent.mkdir(parents=True, exist_ok=True)

    url = f"{BASE_URL}{feed}"
    headers = {"Authorization": f"apikey {settings.require_tfnsw_key()}"}
    started = time.monotonic()
    status: int | None = None
    error: str | None = None

    try:
        with httpx.Client(timeout=settings.download_timeout_seconds) as client:
            with client.stream("GET", url, headers=headers) as response:
                status = response.status_code
                if status != 200:
                    error = response.read()[:500].decode("utf-8", "replace")
                    raise GtfsError(f"HTTP {status} downloading {feed} bundle: {error}")
                # Write beside the target then swap, so an interrupted download cannot
                # leave a truncated zip that later reads treat as valid.
                staging = bundle.path.with_suffix(".part")
                with staging.open("wb") as fh:
                    for chunk in response.iter_bytes(chunk_size=1 << 20):
                        fh.write(chunk)
                staging.replace(bundle.path)
    except httpx.HTTPError as exc:
        error = f"{type(exc).__name__}: {exc}"
        raise GtfsError(error) from exc
    finally:
        moment = now_utc()
        with session_scope() as session:
            session.add(
                ApiCallLog(
                    requested_at=moment,
                    quota_date=quota_day(moment, settings.quota_reset_tz),
                    provider=PROVIDER,
                    endpoint=f"gtfs/schedule/{feed}",
                    attempt=1,
                    http_status=status,
                    latency_ms=int((time.monotonic() - started) * 1000),
                    succeeded=error is None,
                    error=error,
                )
            )

    if not zipfile.is_zipfile(bundle.path):
        bundle.path.unlink(missing_ok=True)
        raise GtfsError(f"{feed} bundle downloaded but is not a valid zip archive")

    log.info("downloaded %s bundle (%.1f MB)", feed, bundle.path.stat().st_size / 1e6)
    return bundle


def ensure_bundle(feed: str, settings: Settings | None = None, force: bool = False) -> GtfsBundle:
    settings = settings or get_settings()
    bundle = bundle_for(feed, settings)
    if force or not bundle.exists() or bundle.age_hours() > settings.gtfs_max_age_hours:
        return download_bundle(feed, settings)
    return bundle
