"""Resolve each watched stop to its Trip Planner ID and its GTFS stop IDs.

These come from two different systems and their identifiers are not assumed to line up,
so both are looked up by name and written to stops.json for you to check. A wrong match
here silently poisons every later sample, which is why it is a separate, inspectable
step rather than something buried in the collector.
"""

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .config import get_settings
from .gtfs.static import GtfsBundle, bundle_for
from .tfnsw.client import TfnswClient
from .tfnsw.stops import find_candidates
from .watchlist import WATCHED

DEFAULT_PATH = Path("stops.json")


@dataclass
class ResolvedStop:
    key: str
    label: str
    trip_planner_id: str
    gtfs_stop_ids: dict[str, set[str]] = field(default_factory=dict)

    def all_gtfs_ids(self) -> set[str]:
        return {sid for ids in self.gtfs_stop_ids.values() for sid in ids}


def _match_gtfs_stops(
    bundle: GtfsBundle, trip_planner_id: str | None, query: str
) -> tuple[list, str]:
    """Find a stop's GTFS rows, preferring exact identifier joins over name similarity.

    Rail feeds link platforms to a station with `parent_station`, and that value is the
    same identifier the Trip Planner uses. The bus feed populates `parent_station` on
    none of its 37,756 stops, so buses fall back to the bare stop ID — which the Trip
    Planner prefixes with `G` and GTFS does not.

    The name fallback matches the *whole* query rather than the part before the first
    comma. "University of Sydney" alone pulls in Parramatta Rd and the Footbridge stops
    as well as City Rd, and once unrelated stops are in the candidate pool a bus can
    match a service that never called at the stop being sampled.
    """
    if not trip_planner_id:
        return [], "none"

    rows = bundle.stops_under(trip_planner_id)
    if rows:
        return rows, "parent_station"

    if trip_planner_id.startswith("G"):
        rows = bundle.stops_under(trip_planner_id[1:])
        if rows:
            return rows, "id_without_prefix"

    rows = bundle.find_stops(query)
    return (rows, "name") if rows else ([], "none")


def resolve_all(client: TfnswClient, bundles: dict[str, GtfsBundle]) -> dict[str, Any]:
    resolved: dict[str, Any] = {}
    for stop in WATCHED:
        candidates = find_candidates(client, stop.query)
        trip_planner_id = candidates[0]["id"] if candidates else None

        gtfs: dict[str, Any] = {}
        for feed, bundle in bundles.items():
            rows, matched_by = _match_gtfs_stops(bundle, trip_planner_id, stop.query)
            gtfs[feed] = {
                "matched_by": matched_by,
                "stop_ids": sorted({r.stop_id for r in rows}),
                "names": sorted({r.stop_name for r in rows})[:12],
            }
        resolved[stop.key] = {
            "label": stop.label,
            "query": stop.query,
            "trip_planner_id": trip_planner_id,
            "trip_planner_name": candidates[0]["name"] if candidates else None,
            "trip_planner_candidates": candidates[:5],
            "gtfs": gtfs,
        }
    return resolved


def save(resolved: dict[str, Any], path: Path = DEFAULT_PATH) -> None:
    path.write_text(json.dumps(resolved, indent=2), encoding="utf-8")


def load(path: Path = DEFAULT_PATH) -> dict[str, ResolvedStop]:
    if not path.exists():
        raise FileNotFoundError(
            f"{path} not found. Run `nextstop resolve-stops` first and check the result."
        )
    raw = json.loads(path.read_text(encoding="utf-8"))

    stops: dict[str, ResolvedStop] = {}
    missing: list[str] = []
    for key, entry in raw.items():
        trip_planner_id = entry.get("trip_planner_id")
        if not trip_planner_id:
            missing.append(key)
            continue
        stops[key] = ResolvedStop(
            key=key,
            label=entry.get("label", key),
            trip_planner_id=str(trip_planner_id),
            gtfs_stop_ids={
                feed: set(data.get("stop_ids") or [])
                for feed, data in (entry.get("gtfs") or {}).items()
            },
        )

    if missing:
        raise ValueError(f"{path} has no trip_planner_id for: {', '.join(missing)}")
    return stops


def open_bundles() -> dict[str, GtfsBundle]:
    return {feed: bundle_for(feed) for feed in get_settings().gtfs_feeds}
