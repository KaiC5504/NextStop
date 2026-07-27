"""Provider-neutral journey shape.

Both the TfNSW and Google parsers normalise into these types so the comparison logic
never has to care which source a journey came from.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


@dataclass
class NormalisedLeg:
    mode: str
    route: str | None
    origin_name: str | None
    destination_name: str | None
    departure_planned: datetime | None
    departure_estimated: datetime | None
    arrival_planned: datetime | None
    arrival_estimated: datetime | None
    duration_seconds: int | None

    @property
    def is_realtime(self) -> bool:
        return self.departure_estimated is not None or self.arrival_estimated is not None

    def as_dict(self) -> dict[str, Any]:
        return {
            "mode": self.mode,
            "route": self.route,
            "origin": self.origin_name,
            "destination": self.destination_name,
            "departure_planned": _iso(self.departure_planned),
            "departure_estimated": _iso(self.departure_estimated),
            "arrival_planned": _iso(self.arrival_planned),
            "arrival_estimated": _iso(self.arrival_estimated),
            "duration_seconds": self.duration_seconds,
        }


@dataclass
class NormalisedJourney:
    rank: int
    legs: list[NormalisedLeg] = field(default_factory=list)

    @property
    def departure_planned(self) -> datetime | None:
        return self.legs[0].departure_planned if self.legs else None

    @property
    def departure_time(self) -> datetime | None:
        """Realtime departure where the provider gave one, otherwise the timetabled time."""
        if not self.legs:
            return None
        first = self.legs[0]
        return first.departure_estimated or first.departure_planned

    @property
    def arrival_time(self) -> datetime | None:
        if not self.legs:
            return None
        last = self.legs[-1]
        return last.arrival_estimated or last.arrival_planned

    @property
    def duration_seconds(self) -> int | None:
        start, end = self.departure_time, self.arrival_time
        if start and end:
            return int((end - start).total_seconds())
        totals = [leg.duration_seconds for leg in self.legs if leg.duration_seconds is not None]
        return sum(totals) if totals else None

    @property
    def is_realtime(self) -> bool:
        return any(leg.is_realtime for leg in self.legs)

    @property
    def mode_sequence(self) -> str:
        return " -> ".join(leg.mode for leg in self.legs)

    def as_legs_json(self) -> list[dict[str, Any]]:
        return [leg.as_dict() for leg in self.legs]


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value else None
