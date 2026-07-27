"""Polling loop.

Every timing decision is made in Sydney local time, so the collector behaves the same
on a Windows box in Sydney as on a VPS in Europe or Singapore.

Volume: 3 stops is 3 calls a poll, roughly 190 TfNSW calls a day against a 60,000
allowance. Quota is nowhere near the constraint; the 10-15s feed refresh is, which is
why nothing polls faster than the sampling interval.
"""

import logging
import threading
import time
from datetime import date, datetime

from .collect import ScheduleCache, StopResult, collect_once
from .gtfs.static import ensure_bundle
from .config import get_settings
from .resolve import ResolvedStop
from .timeutil import now_sydney

# The Chatswood commute window, weekdays. Deliberately wider than the trip itself so
# the run-up to a departure is captured, not just the departure.
COMMUTE_WINDOWS: tuple[tuple[int, int], ...] = ((6, 10), (15, 20))
COMMUTE_INTERVAL_SECONDS = 15 * 60

# Outside the window, an hourly baseline. Showing that schedule and realtime agree when
# nothing is wrong is what makes the peak-hour gap meaningful rather than just noisy.
BASELINE_INTERVAL_SECONDS = 60 * 60

TICK_SECONDS = 20

log = logging.getLogger(__name__)


def in_commute_window(moment: datetime) -> bool:
    if moment.weekday() >= 5:
        return False
    return any(start <= moment.hour < end for start, end in COMMUTE_WINDOWS)


def interval_for(moment: datetime) -> int:
    return COMMUTE_INTERVAL_SECONDS if in_commute_window(moment) else BASELINE_INTERVAL_SECONDS


def run(
    stops: dict[str, ResolvedStop],
    cache: ScheduleCache,
    stop_event: threading.Event | None = None,
) -> None:
    stop_event = stop_event or threading.Event()
    settings = get_settings()
    last_run: float | None = None
    cached_day: date | None = None

    log.info("scheduler started for %s", ", ".join(stops))

    while not stop_event.is_set():
        local = now_sydney()

        # Bound cache growth, and pick up a refreshed bundle at the same time.
        if cached_day is not None and local.date() != cached_day:
            log.info("new service day, clearing schedule cache")
            cache.clear()
            for feed in settings.gtfs_feeds:
                try:
                    ensure_bundle(feed)
                except Exception:
                    log.exception("could not refresh %s bundle; continuing on the cached one", feed)
        cached_day = local.date()

        if last_run is None or (time.monotonic() - last_run) >= interval_for(local):
            last_run = time.monotonic()
            commuting = in_commute_window(local)
            try:
                _log_results(local, commuting, collect_once(stops, cache, local, commuting))
            except Exception:
                # A single bad poll must not kill a week-long collection run.
                log.exception("sampling pass failed; continuing")

        stop_event.wait(TICK_SECONDS)

    log.info("scheduler stopped")


def _log_results(local: datetime, commuting: bool, results: list[StopResult]) -> None:
    ok = sum(1 for r in results if r.ok)
    events = sum(r.events for r in results)
    matched = sum(r.matched for r in results)
    realtime = sum(r.with_realtime for r in results)
    log.info(
        "%s %s poll: %d/%d stops ok, %d departures (%d matched to timetable, %d with realtime)",
        local.strftime("%Y-%m-%d %H:%M"),
        "commute" if commuting else "baseline",
        ok,
        len(results),
        events,
        matched,
        realtime,
    )
    for result in results:
        if not result.ok:
            log.warning("  %s failed: %s", result.stop_key, result.error)
