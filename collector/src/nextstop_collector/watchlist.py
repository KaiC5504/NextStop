"""Stops whose departures Phase 0 samples, per brief §1 (the Chatswood corridor).

Stops are defined by search text, not IDs. Trip Planner IDs and GTFS `stop_id` values
come from different systems and are not assumed to match — both are resolved once into
files you can read and correct. Hardcoding IDs nobody has verified is how you collect a
week of the wrong data without noticing.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class WatchedStop:
    key: str
    label: str
    query: str


# Verified against a live trip plan for home (Chatswood) -> University of
# Sydney: walk to Chatswood, Metro M1 to Central Platform 27, walk to Railway Square,
# bus 412/423/430 to campus. Redfern is deliberately absent — the planner never routes
# through it for this journey, which an earlier guess had assumed it would.
WATCHED: tuple[WatchedStop, ...] = (
    WatchedStop("chatswood", "Chatswood Station", "Chatswood Station"),
    WatchedStop("central", "Central Station", "Central Station"),
    WatchedStop("railway-square", "Railway Square (bus to USyd)", "Railway Square"),
    WatchedStop("usyd-city-rd", "University of Sydney, City Rd", "University of Sydney, City Rd"),
)

BY_KEY: dict[str, WatchedStop] = {s.key: s for s in WATCHED}


def get_stop(key: str) -> WatchedStop:
    try:
        return BY_KEY[key]
    except KeyError:
        raise KeyError(f"unknown stop {key!r}; known: {', '.join(BY_KEY)}") from None
