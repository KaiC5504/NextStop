"""Normalise Trip Planner `trip` responses.

Parsing is deliberately tolerant: this was written from the v3.3 manual before a real
API key existed, so every field access assumes the field may be missing. The first
real response captured by `nextstop collect-once --raw` should become a test fixture
and this module tightened against it.
"""

from typing import Any

from ..journeys import NormalisedJourney, NormalisedLeg
from ..timeutil import parse_api_datetime

# Product classes per the v3.3 manual. Metro (2) is absent from that list but is what
# the Chatswood corridor runs on — confirm against a real response.
PRODUCT_CLASSES: dict[int, str] = {
    1: "Train",
    2: "Metro",
    4: "Light Rail",
    5: "Bus",
    7: "Coach",
    9: "Ferry",
    11: "School Bus",
    99: "Walk",
    100: "Walk",
    107: "Cycle",
}


def _product_name(transportation: dict[str, Any]) -> str:
    product = transportation.get("product") or {}
    raw_class = product.get("class")
    try:
        return PRODUCT_CLASSES.get(int(raw_class), f"Class {raw_class}")
    except (TypeError, ValueError):
        return product.get("name") or "Unknown"


def _place_name(place: dict[str, Any]) -> str | None:
    return place.get("disassembledName") or place.get("name")


def parse_leg(raw: dict[str, Any]) -> NormalisedLeg:
    origin = raw.get("origin") or {}
    destination = raw.get("destination") or {}
    transportation = raw.get("transportation") or {}

    duration = raw.get("duration")
    return NormalisedLeg(
        mode=_product_name(transportation),
        route=transportation.get("number") or transportation.get("disassembledName"),
        origin_name=_place_name(origin),
        destination_name=_place_name(destination),
        departure_planned=parse_api_datetime(origin.get("departureTimePlanned")),
        departure_estimated=parse_api_datetime(origin.get("departureTimeEstimated")),
        arrival_planned=parse_api_datetime(destination.get("arrivalTimePlanned")),
        arrival_estimated=parse_api_datetime(destination.get("arrivalTimeEstimated")),
        duration_seconds=int(duration) if isinstance(duration, (int, float)) else None,
    )


def parse_trip_response(payload: dict[str, Any]) -> list[NormalisedJourney]:
    journeys = payload.get("journeys") or []
    parsed: list[NormalisedJourney] = []
    for rank, journey in enumerate(journeys):
        legs = [parse_leg(leg) for leg in (journey.get("legs") or [])]
        if legs:
            parsed.append(NormalisedJourney(rank=rank, legs=legs))
    return parsed


def parse_service_alerts(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Flatten an `add_info` response into the fields worth storing."""
    infos = payload.get("infos") or {}
    current = infos.get("current") or []
    alerts = []
    for message in current:
        timestamps = message.get("timestamps") or {}
        affected = message.get("affected") or {}
        alerts.append(
            {
                "alert_id": str(message.get("id") or message.get("subtitle") or ""),
                "priority": message.get("priority"),
                "subtitle": message.get("subtitle"),
                "content": message.get("content") or message.get("url"),
                "last_modified": timestamps.get("lastModification"),
                "affected_lines": len(affected.get("lines") or []),
                "affected_stops": len(affected.get("stops") or []),
                "raw": message,
            }
        )
    return alerts
