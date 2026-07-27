"""Parse `departure_mon` responses and match them to the published timetable.

Written from the v3.3 manual before an API key existed, so field access is tolerant of
absences. The first real response should become a fixture.
"""

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any

from ..gtfs.static import ScheduledDeparture
from ..timeutil import parse_api_datetime
from .trip import PRODUCT_CLASSES

MATCH_TOLERANCE = timedelta(seconds=90)


@dataclass
class DepartureEvent:
    stop_id: str
    stop_name: str
    route: str
    destination: str
    mode: str
    planned: datetime
    estimated: datetime | None
    raw: dict[str, Any]

    @property
    def api_delay_seconds(self) -> int | None:
        """Delay according to the Trip Planner itself. Never depends on a static join."""
        if self.estimated is None:
            return None
        return int((self.estimated - self.planned).total_seconds())

    @property
    def effective_departure(self) -> datetime:
        return self.estimated or self.planned


def _mode_name(transportation: dict[str, Any]) -> str:
    product = transportation.get("product") or {}
    try:
        return PRODUCT_CLASSES.get(int(product.get("class")), f"Class {product.get('class')}")
    except (TypeError, ValueError):
        return product.get("name") or "Unknown"


def parse_departure_response(payload: dict[str, Any]) -> list[DepartureEvent]:
    events: list[DepartureEvent] = []
    for event in payload.get("stopEvents") or []:
        planned = parse_api_datetime(event.get("departureTimePlanned"))
        if planned is None:
            continue

        location = event.get("location") or {}
        transportation = event.get("transportation") or {}
        destination = transportation.get("destination") or {}

        events.append(
            DepartureEvent(
                stop_id=str(location.get("id") or ""),
                stop_name=location.get("disassembledName") or location.get("name") or "",
                route=str(transportation.get("number") or transportation.get("name") or ""),
                destination=str(destination.get("name") or ""),
                mode=_mode_name(transportation),
                planned=planned,
                estimated=parse_api_datetime(event.get("departureTimeEstimated")),
                raw=event,
            )
        )
    events.sort(key=lambda e: e.planned)
    return events


def _similarity(event: DepartureEvent, candidate: ScheduledDeparture) -> tuple[int, int, float]:
    """Rank a static candidate against an event: route, then headsign, then closeness."""
    route_match = int(
        bool(event.route)
        and bool(candidate.route_name)
        and event.route.casefold() == candidate.route_name.casefold()
    )
    headsign_match = int(
        bool(event.destination)
        and bool(candidate.headsign)
        and event.destination.casefold() in candidate.headsign.casefold()
    )
    closeness = -abs((candidate.departure - event.planned).total_seconds())
    return (route_match, headsign_match, closeness)


def match_scheduled(
    event: DepartureEvent,
    scheduled: list[ScheduledDeparture],
    tolerance: timedelta = MATCH_TOLERANCE,
) -> ScheduledDeparture | None:
    """Find the timetabled departure this event corresponds to.

    Matches on planned time rather than route name, because the API's route strings and
    GTFS `route_short_name` come from different systems and often disagree in wording.
    Route and headsign only break ties between services leaving at the same minute.
    """
    candidates = [
        s for s in scheduled if abs(s.departure - event.planned) <= tolerance
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda c: _similarity(event, c))
