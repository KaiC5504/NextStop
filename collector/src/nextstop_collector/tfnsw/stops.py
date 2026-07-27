"""Resolve corridor search text to TfNSW stop IDs, cached to a file you can inspect."""

import json
from pathlib import Path
from typing import Any

from ..corridors import CORRIDORS
from .client import TfnswClient

DEFAULT_CACHE = Path("stops.json")


def _score(location: dict[str, Any]) -> tuple[int, int]:
    """Rank Stop Finder candidates: the API's own best flag first, then match quality."""
    is_best = 1 if location.get("isBest") else 0
    quality = location.get("matchQuality") or 0
    return (is_best, int(quality))


def find_candidates(client: TfnswClient, query: str, limit: int = 10) -> list[dict[str, Any]]:
    payload = client.stop_finder(query, max_results=limit)
    locations = payload.get("locations") or []
    ranked = sorted(locations, key=_score, reverse=True)
    return [
        {
            "id": loc.get("id"),
            "name": loc.get("disassembledName") or loc.get("name"),
            "type": loc.get("type"),
            "match_quality": loc.get("matchQuality"),
            "is_best": bool(loc.get("isBest")),
        }
        for loc in ranked
        if loc.get("id")
    ]


def resolve_all(client: TfnswClient) -> dict[str, Any]:
    queries = sorted({c.origin_query for c in CORRIDORS} | {c.destination_query for c in CORRIDORS})
    resolved: dict[str, Any] = {}
    for query in queries:
        candidates = find_candidates(client, query)
        resolved[query] = {
            "chosen_id": candidates[0]["id"] if candidates else None,
            "chosen_name": candidates[0]["name"] if candidates else None,
            "candidates": candidates,
        }
    return resolved


def save(resolved: dict[str, Any], path: Path = DEFAULT_CACHE) -> None:
    path.write_text(json.dumps(resolved, indent=2), encoding="utf-8")


def load(path: Path = DEFAULT_CACHE) -> dict[str, str]:
    """Map of search text -> chosen stop ID."""
    if not path.exists():
        raise FileNotFoundError(
            f"{path} not found. Run `nextstop resolve-stops` first and check the chosen IDs."
        )
    raw = json.loads(path.read_text(encoding="utf-8"))
    mapping = {query: entry.get("chosen_id") for query, entry in raw.items()}
    missing = [q for q, stop_id in mapping.items() if not stop_id]
    if missing:
        raise ValueError(f"{path} has no chosen_id for: {', '.join(missing)}")
    return mapping
