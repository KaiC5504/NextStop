import logging
import random
import time
from datetime import datetime
from typing import Any

import httpx

from ..config import Settings, get_settings
from ..quota import check_quota
from ..ratelimit import TokenBucket
from ..storage.db import session_scope
from ..storage.models import ApiCallLog
from ..timeutil import now_utc, quota_day, to_sydney

BASE_URL = "https://api.transport.nsw.gov.au/v1/tp/"
PROVIDER = "tfnsw"

# 503 shows up well below the documented rate limits, which is the whole reason
# backoff exists here rather than being added later.
RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 504})

log = logging.getLogger(__name__)


class TfnswApiError(RuntimeError):
    pass


class TfnswAuthError(TfnswApiError):
    """Bad or unsubscribed API key. Never retried — retrying just burns quota."""


class TfnswClient:
    def __init__(
        self,
        settings: Settings | None = None,
        http_client: httpx.Client | None = None,
    ) -> None:
        self.settings = settings or get_settings()
        self._bucket = TokenBucket(self.settings.requests_per_second)
        if http_client is not None:
            self._client = http_client
        else:
            self._client = httpx.Client(
                base_url=BASE_URL,
                timeout=self.settings.request_timeout_seconds,
                headers={
                    "Authorization": f"apikey {self.settings.require_tfnsw_key()}",
                    "Accept": "application/json",
                },
            )

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "TfnswClient":
        return self

    def __exit__(self, *exc_info: object) -> None:
        self.close()

    def request(self, endpoint: str, params: dict[str, Any]) -> dict[str, Any]:
        merged: dict[str, Any] = {
            "outputFormat": "rapidJSON",
            "coordOutputFormat": "EPSG:4326",
            **params,
        }
        last_error = "no attempts made"

        for attempt in range(1, self.settings.max_retries + 1):
            self._guard_quota()
            self._bucket.acquire()

            started = time.monotonic()
            status: int | None = None
            try:
                response = self._client.get(endpoint, params=merged)
                status = response.status_code
                latency_ms = int((time.monotonic() - started) * 1000)

                if status == 200:
                    self._log_attempt(endpoint, attempt, status, latency_ms, True, None)
                    return response.json()

                body = response.text[:500]
                if status in (401, 403):
                    self._log_attempt(endpoint, attempt, status, latency_ms, False, body)
                    raise TfnswAuthError(
                        f"HTTP {status} from {endpoint}. Check NEXTSTOP_TFNSW_API_KEY and that "
                        f"the application is subscribed to this API product. Body: {body}"
                    )
                if status not in RETRYABLE_STATUS:
                    self._log_attempt(endpoint, attempt, status, latency_ms, False, body)
                    raise TfnswApiError(f"HTTP {status} from {endpoint}: {body}")

                last_error = f"HTTP {status}: {body}"
            except httpx.HTTPError as exc:
                latency_ms = int((time.monotonic() - started) * 1000)
                last_error = f"{type(exc).__name__}: {exc}"

            self._log_attempt(endpoint, attempt, status, latency_ms, False, last_error)

            if attempt < self.settings.max_retries:
                delay = self._backoff_delay(attempt)
                log.warning(
                    "%s attempt %d/%d failed (%s), retrying in %.1fs",
                    endpoint,
                    attempt,
                    self.settings.max_retries,
                    last_error,
                    delay,
                )
                time.sleep(delay)

        raise TfnswApiError(
            f"{endpoint} failed after {self.settings.max_retries} attempts. Last error: {last_error}"
        )

    def _backoff_delay(self, attempt: int) -> float:
        capped = min(
            self.settings.backoff_base_seconds * (2 ** (attempt - 1)),
            self.settings.backoff_max_seconds,
        )
        # Jitter so repeated collector restarts don't resynchronise into a thundering herd.
        return capped * (0.5 + random.random() * 0.5)

    def _guard_quota(self) -> None:
        with session_scope() as session:
            used, nearly_out = check_quota(
                session,
                PROVIDER,
                quota_day(now_utc(), self.settings.quota_reset_tz),
                self.settings.daily_quota,
            )
        if nearly_out:
            log.warning(
                "TfNSW quota at %d/%d for today", used, self.settings.daily_quota
            )

    def _log_attempt(
        self,
        endpoint: str,
        attempt: int,
        status: int | None,
        latency_ms: int | None,
        succeeded: bool,
        error: str | None,
    ) -> None:
        moment = now_utc()
        with session_scope() as session:
            session.add(
                ApiCallLog(
                    requested_at=moment,
                    quota_date=quota_day(moment, self.settings.quota_reset_tz),
                    provider=PROVIDER,
                    endpoint=endpoint,
                    attempt=attempt,
                    http_status=status,
                    latency_ms=latency_ms,
                    succeeded=succeeded,
                    error=error,
                )
            )

    def trip(
        self,
        origin: str,
        destination: str,
        when: datetime,
        dep_arr: str = "dep",
        origin_type: str = "stop",
        destination_type: str = "stop",
    ) -> dict[str, Any]:
        """Plan a journey. `when` must be timezone-aware; it is sent as Sydney local time."""
        local = to_sydney(when)
        return self.request(
            "trip",
            {
                "depArrMacro": dep_arr,
                "itdDate": local.strftime("%Y%m%d"),
                "itdTime": local.strftime("%H%M"),
                "type_origin": origin_type,
                "name_origin": origin,
                "type_destination": destination_type,
                "name_destination": destination,
                "TfNSWTR": "true",
            },
        )

    def stop_finder(self, query: str, max_results: int = 10) -> dict[str, Any]:
        return self.request(
            "stop_finder",
            {"type_sf": "any", "name_sf": query, "anyMaxSizeHitList": max_results},
        )

    def departures(self, stop_id: str, when: datetime) -> dict[str, Any]:
        local = to_sydney(when)
        return self.request(
            "departure_mon",
            {
                "mode": "direct",
                "type_dm": "stop",
                "name_dm": stop_id,
                "depArrMacro": "dep",
                "itdDate": local.strftime("%Y%m%d"),
                "itdTime": local.strftime("%H%M"),
                "TfNSWDM": "true",
            },
        )

    def service_alerts(self, when: datetime, stop_id: str | None = None) -> dict[str, Any]:
        local = to_sydney(when)
        params: dict[str, Any] = {
            "filterDateValid": local.strftime("%d-%m-%Y"),
            "filterPublicationStatus": "current",
        }
        if stop_id:
            params["itdLPxx_selStop"] = stop_id
        return self.request("add_info", params)
