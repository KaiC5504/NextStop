"""One sampling pass: for each watched stop, what does the timetable say and what is
actually happening?

The same departure is deliberately sampled on every poll as it approaches. Watching an
estimate move is more informative than a single reading, and it is what shows whether
the Trip Planner reacts to a delay before it happens or only after.
"""

import logging
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from .gtfs.static import GtfsBundle, ScheduledDeparture
from .resolve import ResolvedStop
from .storage.db import session_scope
from .storage.models import DepartureSample, ServiceAlert
from .tfnsw import trip as tfnsw_trip
from .tfnsw.client import TfnswClient
from .tfnsw.departures import DepartureEvent, match_scheduled, parse_departure_response
from .timeutil import now_utc, quota_day, to_sydney

log = logging.getLogger(__name__)


@dataclass
class StopResult:
    stop_key: str
    events: int = 0
    matched: int = 0
    with_realtime: int = 0
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


class ScheduleCache:
    """Memoises parsed timetables.

    Streaming stop_times.txt costs seconds on the larger bundles, and the timetable for
    a given service day does not change between polls, so parsing it once per day per
    feed rather than once every fifteen minutes matters.
    """

    def __init__(self, bundles: dict[str, GtfsBundle]) -> None:
        self.bundles = bundles
        self._cache: dict[tuple[str, date, frozenset[str]], list[ScheduledDeparture]] = {}

    def get(self, feed: str, stop_ids: set[str], service_day: date) -> list[ScheduledDeparture]:
        key = (feed, service_day, frozenset(stop_ids))
        if key not in self._cache:
            bundle = self.bundles.get(feed)
            if bundle is None or not stop_ids:
                self._cache[key] = []
            else:
                self._cache[key] = bundle.scheduled_departures(stop_ids, service_day)
                log.debug(
                    "cached %d scheduled departures for %s on %s",
                    len(self._cache[key]),
                    feed,
                    service_day,
                )
        return self._cache[key]

    def for_stop(self, stop: ResolvedStop, service_days: list[date]) -> list[ScheduledDeparture]:
        combined: list[ScheduledDeparture] = []
        for feed, stop_ids in stop.gtfs_stop_ids.items():
            for service_day in service_days:
                combined.extend(self.get(feed, stop_ids, service_day))
        return combined

    def clear(self) -> None:
        self._cache.clear()


def service_days_for(moment: datetime) -> list[date]:
    """Service days that can contain departures visible right now.

    Yesterday is included because GTFS expresses after-midnight services as hours past
    24 on the previous service day, so a 00:20 departure is 24:20 on yesterday's date.
    """
    local = to_sydney(moment).date()
    return [local - timedelta(days=1), local]


def _sample_from(
    event: DepartureEvent,
    scheduled: ScheduledDeparture | None,
    stop: ResolvedStop,
    polled_at: datetime,
) -> DepartureSample:
    naive_gap = None
    planned_vs_scheduled = None
    if scheduled is not None:
        planned_vs_scheduled = int((event.planned - scheduled.departure).total_seconds())
        if event.estimated is not None:
            naive_gap = int((event.estimated - scheduled.departure).total_seconds())

    return DepartureSample(
        polled_at=polled_at,
        quota_date=quota_day(polled_at),
        stop_key=stop.key,
        stop_id=event.stop_id or stop.trip_planner_id,
        route=event.route[:128],
        destination=event.destination[:128],
        mode=event.mode[:32],
        planned_departure=event.planned,
        estimated_departure=event.estimated,
        scheduled_departure=scheduled.departure if scheduled else None,
        api_delay_seconds=event.api_delay_seconds,
        naive_gap_seconds=naive_gap,
        planned_vs_scheduled_seconds=planned_vs_scheduled,
        matched_static=scheduled is not None,
        gtfs_trip_id=scheduled.trip_id if scheduled else None,
        gtfs_feed=scheduled.feed if scheduled else None,
        raw=event.raw,
    )


def collect_stop(
    client: TfnswClient,
    stop: ResolvedStop,
    cache: ScheduleCache,
    when: datetime,
) -> StopResult:
    try:
        raw = client.departures(stop.trip_planner_id, when)
    except Exception as exc:
        log.error("departures failed for %s: %s", stop.key, exc)
        return StopResult(stop.key, error=str(exc))

    events = parse_departure_response(raw)
    scheduled = cache.for_stop(stop, service_days_for(when))
    polled_at = now_utc()

    result = StopResult(stop.key, events=len(events))
    with session_scope() as session:
        for event in events:
            match = match_scheduled(event, scheduled)
            if match is not None:
                result.matched += 1
            if event.estimated is not None:
                result.with_realtime += 1
            session.add(_sample_from(event, match, stop, polled_at))

    if events and not result.matched:
        log.warning(
            "%s: %d departures but none matched the timetable — check stops.json GTFS ids",
            stop.key,
            len(events),
        )
    return result


def collect_service_alerts(client: TfnswClient, when: datetime) -> int:
    raw = client.service_alerts(when)
    alerts = tfnsw_trip.parse_service_alerts(raw)
    moment = now_utc()
    with session_scope() as session:
        for alert in alerts:
            session.add(
                ServiceAlert(
                    fetched_at=moment,
                    alert_id=alert["alert_id"],
                    priority=alert["priority"],
                    subtitle=alert["subtitle"],
                    content=alert["content"],
                    raw=alert["raw"],
                )
            )
    return len(alerts)


def collect_once(
    stops: dict[str, ResolvedStop],
    cache: ScheduleCache,
    when: datetime,
    include_alerts: bool = False,
) -> list[StopResult]:
    results: list[StopResult] = []
    with TfnswClient() as client:
        for stop in stops.values():
            results.append(collect_stop(client, stop, cache, when))
        if include_alerts:
            log.info("stored %d service alerts", collect_service_alerts(client, when))
    return results
