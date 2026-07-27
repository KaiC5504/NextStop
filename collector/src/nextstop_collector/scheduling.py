"""Polling loop.

Every timing decision is made in Sydney local time, so the collector behaves the same
on a Windows box in Sydney as on a VPS in Europe or Singapore.

Volume check: 4 corridors x 4 TfNSW calls per poll, ~72 peak polls plus ~18 off-peak
polls a day, is roughly 400 TfNSW calls/day against a 60,000 allowance. The limit is
not the constraint here; the 10-15s feed refresh is, which is why nothing polls faster
than five minutes.
"""

import logging
import threading
import time
from datetime import datetime

from .collect import CollectionResult, collect_once
from .timeutil import now_sydney

PEAK_WINDOWS: tuple[tuple[int, int], ...] = ((7, 10), (16, 19))
PEAK_INTERVAL_SECONDS = 300
OFFPEAK_INTERVAL_SECONDS = 3600
TICK_SECONDS = 15

log = logging.getLogger(__name__)


def is_peak(moment: datetime) -> bool:
    if moment.weekday() >= 5:
        return False
    return any(start <= moment.hour < end for start, end in PEAK_WINDOWS)


def interval_for(moment: datetime) -> int:
    return PEAK_INTERVAL_SECONDS if is_peak(moment) else OFFPEAK_INTERVAL_SECONDS


def run(
    corridor_keys: list[str],
    include_google: bool = True,
    stop_event: threading.Event | None = None,
) -> None:
    stop_event = stop_event or threading.Event()
    last_run: float | None = None

    log.info(
        "scheduler started for %s (google=%s)", ", ".join(corridor_keys), include_google
    )

    while not stop_event.is_set():
        local = now_sydney()
        interval = interval_for(local)
        due = last_run is None or (time.monotonic() - last_run) >= interval

        if due:
            last_run = time.monotonic()
            peak = is_peak(local)
            try:
                results = collect_once(
                    corridor_keys,
                    when=local,
                    include_google=include_google,
                    include_alerts=peak,
                )
                _log_results(local, peak, results)
            except Exception:
                # A single bad poll must not kill a week-long collection run.
                log.exception("collection pass failed; continuing")

        stop_event.wait(TICK_SECONDS)

    log.info("scheduler stopped")


def _log_results(local: datetime, peak: bool, results: list[CollectionResult]) -> None:
    ok = sum(1 for r in results if r.ok)
    journeys = sum(r.journey_count for r in results)
    log.info(
        "%s %s poll: %d/%d requests ok, %d journeys stored",
        local.strftime("%Y-%m-%d %H:%M"),
        "peak" if peak else "off-peak",
        ok,
        len(results),
        journeys,
    )
    for result in results:
        if not result.ok:
            log.warning("  %s/%s failed: %s", result.provider, result.corridor, result.error)
