"""The routes Phase 0 collects, per brief §1: the Chatswood <-> city / USyd corridor.

Endpoints are defined as search text rather than stop IDs. IDs are resolved once via
Stop Finder into stops.json, which you can read and correct by hand — hardcoding IDs
that nobody has verified against the live API is how you collect a week of the wrong
data without noticing.
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class Corridor:
    key: str
    label: str
    origin_query: str
    destination_query: str

    # Coordinates for the Google arm, which takes lat/lng rather than TfNSW stop IDs.
    origin_latlng: tuple[float, float]
    destination_latlng: tuple[float, float]


CHATSWOOD = (-33.7965, 151.1832)
CENTRAL = (-33.8832, 151.2065)
USYD = (-33.8886, 151.1873)

CORRIDORS: tuple[Corridor, ...] = (
    Corridor(
        key="chatswood-central",
        label="Chatswood -> Central",
        origin_query="Chatswood Station",
        destination_query="Central Station",
        origin_latlng=CHATSWOOD,
        destination_latlng=CENTRAL,
    ),
    Corridor(
        key="central-chatswood",
        label="Central -> Chatswood",
        origin_query="Central Station",
        destination_query="Chatswood Station",
        origin_latlng=CENTRAL,
        destination_latlng=CHATSWOOD,
    ),
    Corridor(
        key="chatswood-usyd",
        label="Chatswood -> University of Sydney",
        origin_query="Chatswood Station",
        destination_query="University of Sydney",
        origin_latlng=CHATSWOOD,
        destination_latlng=USYD,
    ),
    Corridor(
        key="usyd-chatswood",
        label="University of Sydney -> Chatswood",
        origin_query="University of Sydney",
        destination_query="Chatswood Station",
        origin_latlng=USYD,
        destination_latlng=CHATSWOOD,
    ),
)

BY_KEY: dict[str, Corridor] = {c.key: c for c in CORRIDORS}


def get_corridor(key: str) -> Corridor:
    try:
        return BY_KEY[key]
    except KeyError:
        raise KeyError(f"unknown corridor {key!r}; known: {', '.join(BY_KEY)}") from None
