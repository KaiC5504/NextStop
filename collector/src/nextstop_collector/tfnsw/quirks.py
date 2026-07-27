"""GTFS-Realtime handling for the Sydney feeds, per brief §4.

These filters are what stop the app showing things Google gets wrong: non-revenue
movements, the same train twice, stops the vehicle passes without stopping, and
altered/replacement services during trackwork.

This module is pure — it takes parsed protobuf and returns parsed protobuf — so it is
fully testable on Windows with synthetic feeds and no API key. It is also the layer
that gets ported to Swift, so it deliberately avoids depending on storage or HTTP.
"""

from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field

from google.transit import gtfs_realtime_pb2

_TripSR = gtfs_realtime_pb2.TripDescriptor
_StopSR = gtfs_realtime_pb2.TripUpdate.StopTimeUpdate

# Non-revenue movements: empty cars being repositioned. Never show these to a user.
NON_REVENUE_ROUTE_IDS = frozenset({"RTTA_DEF", "RTTA_REV"})

# REPLACEMENT (5) was dropped from the GTFS-RT spec but Sydney Trains still emits it.
# The official Python bindings do still define the value, so it parses cleanly — the
# real failure mode is downstream code that switches on schedule_relationship with no
# REPLACEMENT branch and silently treats these as ordinary scheduled services. Which is
# exactly the trackwork case we care about, so it gets classified explicitly.
ALTERED_RELATIONSHIPS = frozenset(
    {_TripSR.ADDED, _TripSR.REPLACEMENT, _TripSR.DUPLICATED, _TripSR.NEW}
)
CANCELLED_RELATIONSHIPS = frozenset({_TripSR.CANCELED, _TripSR.DELETED})

# GTFS pickup_type / drop_off_type: 1 means the service does not pick up / set down here.
_NOT_AVAILABLE = 1


@dataclass(frozen=True)
class QuirkConfig:
    non_revenue_route_ids: frozenset[str] = NON_REVENUE_ROUTE_IDS
    # Charter route IDs are not documented publicly; collect them from real feeds and
    # add them here rather than guessing at a pattern.
    charter_route_ids: frozenset[str] = field(default_factory=frozenset)


DEFAULT_CONFIG = QuirkConfig()


def trip_descriptor(entity: gtfs_realtime_pb2.FeedEntity) -> gtfs_realtime_pb2.TripDescriptor | None:
    if entity.HasField("trip_update"):
        return entity.trip_update.trip
    if entity.HasField("vehicle"):
        return entity.vehicle.trip
    return None


def route_id(entity: gtfs_realtime_pb2.FeedEntity) -> str:
    trip = trip_descriptor(entity)
    return trip.route_id if trip else ""


def trip_key(entity: gtfs_realtime_pb2.FeedEntity) -> tuple[str, str, str]:
    """Identity used to spot the same service arriving from two overlapping feeds."""
    trip = trip_descriptor(entity)
    if trip is None:
        return ("", "", "")
    return (trip.trip_id, trip.start_date, trip.route_id)


def is_non_revenue(
    entity: gtfs_realtime_pb2.FeedEntity, config: QuirkConfig = DEFAULT_CONFIG
) -> bool:
    rid = route_id(entity)
    return rid in config.non_revenue_route_ids or rid in config.charter_route_ids


def classify_trip(entity: gtfs_realtime_pb2.FeedEntity) -> str:
    """One of: scheduled, altered, cancelled, unscheduled, unknown."""
    trip = trip_descriptor(entity)
    if trip is None:
        return "unknown"
    relationship = trip.schedule_relationship
    if relationship in CANCELLED_RELATIONSHIPS:
        return "cancelled"
    if relationship in ALTERED_RELATIONSHIPS:
        return "altered"
    if relationship == _TripSR.UNSCHEDULED:
        return "unscheduled"
    return "scheduled"


def is_boardable(update: _StopSR) -> bool:
    """False for stops the vehicle passes, or stops where nobody may board."""
    if update.schedule_relationship == _StopSR.SKIPPED:
        return False
    if update.HasField("stop_time_properties"):
        if update.stop_time_properties.pickup_type == _NOT_AVAILABLE:
            return False
    return True


def can_alight(update: _StopSR) -> bool:
    if update.schedule_relationship == _StopSR.SKIPPED:
        return False
    if update.HasField("stop_time_properties"):
        if update.stop_time_properties.drop_off_type == _NOT_AVAILABLE:
            return False
    return True


def boardable_stops(entity: gtfs_realtime_pb2.FeedEntity) -> list[_StopSR]:
    if not entity.HasField("trip_update"):
        return []
    return [u for u in entity.trip_update.stop_time_update if is_boardable(u)]


def revenue_entities(
    feed: gtfs_realtime_pb2.FeedMessage, config: QuirkConfig = DEFAULT_CONFIG
) -> Iterator[gtfs_realtime_pb2.FeedEntity]:
    for entity in feed.entity:
        if not is_non_revenue(entity, config):
            yield entity


def dedupe_across_feeds(
    feeds: Iterable[gtfs_realtime_pb2.FeedMessage],
    config: QuirkConfig = DEFAULT_CONFIG,
) -> list[gtfs_realtime_pb2.FeedEntity]:
    """Merge overlapping feeds (the NSW Trains and Sydney Trains feeds share services).

    First feed wins on collision, so pass the more authoritative feed first.
    """
    seen: set[tuple[str, str, str]] = set()
    merged: list[gtfs_realtime_pb2.FeedEntity] = []
    for feed in feeds:
        for entity in revenue_entities(feed, config):
            key = trip_key(entity)
            if key == ("", "", "") or key in seen:
                continue
            seen.add(key)
            merged.append(entity)
    return merged
