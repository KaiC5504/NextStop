"""Google Routes API transit client — the comparison arm for Phase 0.

Uses computeRoutes (the Directions API successor). Written from Google's published
request/response shape; like the TfNSW parser it is tolerant of missing fields and
should be tightened once real responses are captured.
"""

import logging
import time
from datetime import datetime, timezone
from typing import Any

import httpx

from ..config import Settings, get_settings
from ..journeys import NormalisedJourney, NormalisedLeg
from ..ratelimit import TokenBucket
from ..storage.db import session_scope
from ..storage.models import ApiCallLog
from ..timeutil import now_utc, parse_api_datetime, quota_day

ENDPOINT = "https://routes.googleapis.com/directions/v2:computeRoutes"
PROVIDER = "google"

# Routes API rejects requests without an explicit field mask.
FIELD_MASK = ",".join(
    [
        "routes.duration",
        "routes.legs.duration",
        "routes.legs.steps.travelMode",
        "routes.legs.steps.transitDetails",
    ]
)

VEHICLE_MODES: dict[str, str] = {
    "BUS": "Bus",
    "SUBWAY": "Metro",
    "METRO_RAIL": "Metro",
    "HEAVY_RAIL": "Train",
    "COMMUTER_TRAIN": "Train",
    "RAIL": "Train",
    "TRAIN": "Train",
    "LIGHT_RAIL": "Light Rail",
    "TRAM": "Light Rail",
    "FERRY": "Ferry",
}

log = logging.getLogger(__name__)


class GoogleRoutesError(RuntimeError):
    pass


class GoogleRoutesClient:
    def __init__(
        self, settings: Settings | None = None, http_client: httpx.Client | None = None
    ) -> None:
        self.settings = settings or get_settings()
        self._bucket = TokenBucket(self.settings.requests_per_second)
        if http_client is not None:
            self._client = http_client
        else:
            self._client = httpx.Client(
                timeout=self.settings.request_timeout_seconds,
                headers={
                    "Content-Type": "application/json",
                    "X-Goog-Api-Key": self.settings.require_google_key(),
                    "X-Goog-FieldMask": FIELD_MASK,
                },
            )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "GoogleRoutesClient":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    def compute_routes(
        self,
        origin: tuple[float, float],
        destination: tuple[float, float],
        departure: datetime,
    ) -> dict[str, Any]:
        body = {
            "origin": _waypoint(origin),
            "destination": _waypoint(destination),
            "travelMode": "TRANSIT",
            "departureTime": departure.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "computeAlternativeRoutes": True,
        }

        self._bucket.acquire()
        started = time.monotonic()
        status: int | None = None
        try:
            response = self._client.post(ENDPOINT, json=body)
            status = response.status_code
            latency_ms = int((time.monotonic() - started) * 1000)
            if status == 200:
                self._log_attempt(status, latency_ms, True, None)
                return response.json()
            body_text = response.text[:500]
            self._log_attempt(status, latency_ms, False, body_text)
            raise GoogleRoutesError(f"HTTP {status} from Routes API: {body_text}")
        except httpx.HTTPError as exc:
            latency_ms = int((time.monotonic() - started) * 1000)
            error = f"{type(exc).__name__}: {exc}"
            self._log_attempt(status, latency_ms, False, error)
            raise GoogleRoutesError(error) from exc

    def _log_attempt(
        self, status: int | None, latency_ms: int, succeeded: bool, error: str | None
    ) -> None:
        moment = now_utc()
        with session_scope() as session:
            session.add(
                ApiCallLog(
                    requested_at=moment,
                    quota_date=quota_day(moment, self.settings.quota_reset_tz),
                    provider=PROVIDER,
                    endpoint="computeRoutes",
                    attempt=1,
                    http_status=status,
                    latency_ms=latency_ms,
                    succeeded=succeeded,
                    error=error,
                )
            )


def _waypoint(latlng: tuple[float, float]) -> dict[str, Any]:
    return {"location": {"latLng": {"latitude": latlng[0], "longitude": latlng[1]}}}


def _duration_seconds(raw: str | None) -> int | None:
    """Routes API durations are strings like '1234s'."""
    if not raw or not raw.endswith("s"):
        return None
    try:
        return int(float(raw[:-1]))
    except ValueError:
        return None


def _parse_step(step: dict[str, Any]) -> NormalisedLeg | None:
    travel_mode = step.get("travelMode")
    details = step.get("transitDetails") or {}

    if travel_mode == "WALK" or not details:
        return None

    stop_details = details.get("stopDetails") or {}
    line = (details.get("transitLine") or {})
    vehicle_type = ((line.get("vehicle") or {}).get("type")) or ""

    departure = parse_api_datetime(stop_details.get("departureTime"))
    arrival = parse_api_datetime(stop_details.get("arrivalTime"))
    duration = None
    if departure and arrival:
        duration = int((arrival - departure).total_seconds())

    return NormalisedLeg(
        mode=VEHICLE_MODES.get(vehicle_type, vehicle_type.title() or "Transit"),
        route=line.get("nameShort") or line.get("name"),
        origin_name=(stop_details.get("departureStop") or {}).get("name"),
        destination_name=(stop_details.get("arrivalStop") or {}).get("name"),
        # Google does not distinguish timetabled from realtime in the response, so its
        # times land in the planned fields and is_realtime stays False for this provider.
        departure_planned=departure,
        departure_estimated=None,
        arrival_planned=arrival,
        arrival_estimated=None,
        duration_seconds=duration,
    )


def parse_routes_response(payload: dict[str, Any]) -> list[NormalisedJourney]:
    journeys: list[NormalisedJourney] = []
    for rank, route in enumerate(payload.get("routes") or []):
        legs: list[NormalisedLeg] = []
        for leg in route.get("legs") or []:
            for step in leg.get("steps") or []:
                parsed = _parse_step(step)
                if parsed:
                    legs.append(parsed)
        if legs:
            journeys.append(NormalisedJourney(rank=rank, legs=legs))
    return journeys
