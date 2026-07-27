"""One collection pass: ask both providers to plan the same journey, store both answers."""

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from .corridors import Corridor, get_corridor
from .googlemaps import routes as google_routes
from .journeys import NormalisedJourney
from .storage.db import session_scope
from .storage.models import ServiceAlert, TripOption, TripQuery
from .tfnsw import client as tfnsw_client
from .tfnsw import stops as tfnsw_stops
from .tfnsw import trip as tfnsw_trip
from .timeutil import now_utc, quota_day

log = logging.getLogger(__name__)


@dataclass
class CollectionResult:
    provider: str
    corridor: str
    journey_count: int
    query_id: int | None = None
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.error is None


def _persist(
    provider: str,
    corridor: Corridor,
    origin_ref: str,
    destination_ref: str,
    depart_after: datetime,
    raw: dict[str, Any] | None,
    journeys: list[NormalisedJourney],
    http_status: int | None,
    error: str | None,
) -> int:
    moment = now_utc()
    with session_scope() as session:
        query = TripQuery(
            requested_at=moment,
            quota_date=quota_day(moment),
            provider=provider,
            corridor=corridor.key,
            origin_ref=origin_ref,
            destination_ref=destination_ref,
            depart_after=depart_after,
            http_status=http_status,
            error=error,
            raw_response=raw,
        )
        session.add(query)
        session.flush()

        for journey in journeys:
            session.add(
                TripOption(
                    query_id=query.id,
                    rank=journey.rank,
                    departure_time=journey.departure_time,
                    arrival_time=journey.arrival_time,
                    duration_seconds=journey.duration_seconds,
                    is_realtime=journey.is_realtime,
                    departure_planned=journey.departure_planned,
                    mode_sequence=journey.mode_sequence,
                    leg_count=len(journey.legs),
                    legs=journey.as_legs_json(),
                )
            )
        return query.id


def collect_tfnsw(
    client: tfnsw_client.TfnswClient,
    corridor: Corridor,
    stop_ids: dict[str, str],
    when: datetime,
) -> CollectionResult:
    origin = stop_ids[corridor.origin_query]
    destination = stop_ids[corridor.destination_query]
    try:
        raw = client.trip(origin, destination, when)
    except Exception as exc:
        query_id = _persist(
            tfnsw_client.PROVIDER, corridor, origin, destination, when, None, [], None, str(exc)
        )
        log.error("TfNSW collection failed for %s: %s", corridor.key, exc)
        return CollectionResult(tfnsw_client.PROVIDER, corridor.key, 0, query_id, str(exc))

    journeys = tfnsw_trip.parse_trip_response(raw)
    query_id = _persist(
        tfnsw_client.PROVIDER, corridor, origin, destination, when, raw, journeys, 200, None
    )
    return CollectionResult(tfnsw_client.PROVIDER, corridor.key, len(journeys), query_id)


def collect_google(
    client: google_routes.GoogleRoutesClient, corridor: Corridor, when: datetime
) -> CollectionResult:
    origin = f"{corridor.origin_latlng[0]},{corridor.origin_latlng[1]}"
    destination = f"{corridor.destination_latlng[0]},{corridor.destination_latlng[1]}"
    try:
        raw = client.compute_routes(corridor.origin_latlng, corridor.destination_latlng, when)
    except Exception as exc:
        query_id = _persist(
            google_routes.PROVIDER, corridor, origin, destination, when, None, [], None, str(exc)
        )
        log.error("Google collection failed for %s: %s", corridor.key, exc)
        return CollectionResult(google_routes.PROVIDER, corridor.key, 0, query_id, str(exc))

    journeys = google_routes.parse_routes_response(raw)
    query_id = _persist(
        google_routes.PROVIDER, corridor, origin, destination, when, raw, journeys, 200, None
    )
    return CollectionResult(google_routes.PROVIDER, corridor.key, len(journeys), query_id)


def collect_service_alerts(client: tfnsw_client.TfnswClient, when: datetime) -> int:
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
    corridor_keys: list[str],
    when: datetime,
    include_google: bool = True,
    include_alerts: bool = False,
) -> list[CollectionResult]:
    corridors = [get_corridor(key) for key in corridor_keys]
    stop_ids = tfnsw_stops.load()
    results: list[CollectionResult] = []

    with tfnsw_client.TfnswClient() as tfnsw:
        for corridor in corridors:
            results.append(collect_tfnsw(tfnsw, corridor, stop_ids, when))
        if include_alerts:
            count = collect_service_alerts(tfnsw, when)
            log.info("stored %d service alerts", count)

    if include_google:
        with google_routes.GoogleRoutesClient() as google:
            for corridor in corridors:
                results.append(collect_google(google, corridor, when))

    return results
