"""Stop Finder lookups."""

from typing import Any

from .client import TfnswClient


def _score(location: dict[str, Any]) -> tuple[int, int]:
    """Rank candidates: the API's own best flag first, then match quality."""
    is_best = 1 if location.get("isBest") else 0
    quality = location.get("matchQuality") or 0
    return (is_best, int(quality))


def find_candidates(client: TfnswClient, query: str, limit: int = 10) -> list[dict[str, Any]]:
    payload = client.stop_finder(query, max_results=limit)
    locations = payload.get("locations") or []
    ranked = sorted(locations, key=_score, reverse=True)
    return [
        {
            "id": str(loc.get("id")),
            "name": loc.get("disassembledName") or loc.get("name"),
            "type": loc.get("type"),
            "match_quality": loc.get("matchQuality"),
            "is_best": bool(loc.get("isBest")),
        }
        for loc in ranked
        if loc.get("id")
    ]
