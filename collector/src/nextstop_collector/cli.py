import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import typer
from rich.console import Console
from rich.logging import RichHandler
from rich.table import Table

from . import resolve as resolve_module
from . import scheduling
from . import timetable as timetable_module
from .collect import Timetables, collect_once, service_days_for
from .config import get_settings
from .gtfs.static import ensure_bundle
from .quota import calls_used
from .storage.db import init_db, session_scope
from .storage.models import Observation
from .tfnsw.client import TfnswClient
from .timeutil import now_sydney, now_utc, quota_day, to_sydney
from .watchlist import BY_KEY

app = typer.Typer(help="NextStop Phase 0 collector", no_args_is_help=True)
console = Console()


def _setup_logging(verbose: bool = False) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(message)s",
        datefmt="%H:%M:%S",
        handlers=[RichHandler(console=console, rich_tracebacks=True, show_path=False)],
    )


def _select_stops(stop: str) -> dict[str, resolve_module.ResolvedStop]:
    stops = resolve_module.load()
    if stop == "all":
        return stops
    if stop not in stops:
        raise typer.BadParameter(f"unknown stop {stop!r}; known: {', '.join(stops)}, all")
    return {stop: stops[stop]}


@app.command("init-db")
def init_db_command() -> None:
    """Create the SQLite schema."""
    _setup_logging()
    init_db()
    console.print(f"[green]schema ready[/] at {get_settings().database_url}")


@app.command("gtfs-refresh")
def gtfs_refresh_command(
    feed: str = typer.Option("all", help="Feed name, or 'all'"),
    force: bool = typer.Option(False, help="Re-download even if the cache is fresh"),
) -> None:
    """Download the static GTFS bundles used as the published-timetable baseline."""
    _setup_logging()
    init_db()
    settings = get_settings()
    feeds = list(settings.gtfs_feeds) if feed == "all" else [feed]

    today = now_sydney().date()
    stale: list[str] = []

    table = Table(title="GTFS bundles")
    table.add_column("Feed")
    table.add_column("API", justify="center")
    table.add_column("Size", justify="right")
    table.add_column("Timetable covers")
    table.add_column("Today")
    for name in feeds:
        bundle = ensure_bundle(name, force=force)
        span = bundle.calendar_range()
        covers = bundle.covers(today)
        if not covers:
            stale.append(name)
        table.add_row(
            name,
            settings.feed_version(name),
            f"{bundle.path.stat().st_size / 1e6:.1f} MB",
            f"{span[0]} to {span[1]}" if span else "[red]no calendar[/]",
            "[green]yes[/]" if covers else "[red]NO[/]",
        )
    console.print(table)

    if stale:
        console.print(
            f"\n[red]{', '.join(stale)} does not cover today.[/] An expired bundle returns no "
            "active services rather than an error, so every departure would go unmatched and "
            "the comparison would silently measure nothing. Check the feed's API version in "
            "Settings.gtfs_feed_versions before collecting."
        )


@app.command("build-timetable")
def build_timetable_command(
    ahead: int = typer.Option(0, help="Also build this many days beyond today"),
    prune: bool = typer.Option(True, help="Drop stored timetables older than 30 days"),
) -> None:
    """Parse the published timetable into the database.

    This is the slow step — around 150 seconds for the bus bundle. Doing it once a day
    here is what lets each sampling run start in about a second, so the collector does
    not need to be a long-running process.
    """
    _setup_logging()
    init_db()
    stops = _select_stops("all")
    bundles = {feed: ensure_bundle(feed) for feed in get_settings().gtfs_feeds}

    days = service_days_for(now_sydney())
    days += [days[-1] + timedelta(days=n) for n in range(1, ahead + 1)]
    Timetables(bundles, stops).ensure(days)

    if prune:
        removed = timetable_module.prune()
        if removed:
            console.print(f"pruned {removed} old timetable entries")

    table = Table(title="Stored timetables")
    table.add_column("Feed")
    table.add_column("Service day")
    table.add_column("Departures", justify="right")
    table.add_column("Built (UTC)")
    for feed, service_day, count, built_at in timetable_module.status():
        table.add_row(feed, str(service_day), str(count), built_at.strftime("%Y-%m-%d %H:%M"))
    console.print(table)


@app.command("resolve-stops")
def resolve_stops_command(
    output: Path = typer.Option(resolve_module.DEFAULT_PATH, help="Where to write stops.json"),
) -> None:
    """Resolve each watched stop to a Trip Planner ID and its GTFS stop IDs."""
    _setup_logging()
    init_db()
    bundles = {feed: ensure_bundle(feed) for feed in get_settings().gtfs_feeds}
    with TfnswClient() as client:
        resolved = resolve_module.resolve_all(client, bundles)
    resolve_module.save(resolved, output)

    table = Table(title="Resolved stops — confirm these before collecting a week of data")
    table.add_column("Stop")
    table.add_column("Trip Planner ID")
    table.add_column("Matched name")
    table.add_column("GTFS stop IDs", justify="right")
    name_matched: list[str] = []
    for key, entry in resolved.items():
        parts = []
        for feed, data in entry["gtfs"].items():
            count = len(data["stop_ids"])
            if data["matched_by"] == "name" and count:
                name_matched.append(f"{key}/{feed}")
                parts.append(f"[yellow]{feed}:{count}?[/]")
            elif count:
                parts.append(f"{feed}:{count}")
        table.add_row(
            key,
            entry["trip_planner_id"] or "[red]none[/]",
            entry["trip_planner_name"] or "-",
            ", ".join(parts) or "-",
        )
    console.print(table)

    if name_matched:
        console.print(
            f"\n[yellow]Matched by name, not by parent_station: {', '.join(name_matched)}.[/] "
            "The exact identifier join failed for these, so the GTFS stop IDs are a guess "
            "and may pull in a different stop. Check their names in the file."
        )
    console.print(
        f"\nWritten to [bold]{output}[/]. A wrong match here poisons every later sample, "
        "so check the names in the file before starting a collection run."
    )


@app.command("collect-once")
def collect_once_command(
    stop: str = typer.Option("all", help="Watched stop key, or 'all'"),
    alerts: bool = typer.Option(False, help="Also snapshot service alerts"),
    raw: bool = typer.Option(False, help="Print a raw stop event for fixture capture"),
) -> None:
    """Run a single sampling pass now."""
    _setup_logging()
    init_db()
    stops = _select_stops(stop)
    bundles = {feed: ensure_bundle(feed) for feed in get_settings().gtfs_feeds}
    timetables = Timetables(bundles, stops)
    results = collect_once(stops, timetables, now_sydney(), include_alerts=alerts)

    table = Table(title="Sampling results")
    table.add_column("Stop")
    table.add_column("Departures", justify="right")
    table.add_column("Matched timetable", justify="right")
    table.add_column("With realtime", justify="right")
    table.add_column("Status")
    for result in results:
        table.add_row(
            result.stop_key,
            str(result.events),
            str(result.matched),
            str(result.with_realtime),
            "[green]ok[/]" if result.ok else f"[red]{result.error[:60]}[/]",
        )
    console.print(table)

    if raw:
        from sqlalchemy import select

        from .storage.models import DepartureSample

        with session_scope() as session:
            sample = session.execute(
                select(DepartureSample).order_by(DepartureSample.id.desc()).limit(1)
            ).scalar_one_or_none()
            if sample and sample.raw:
                console.print("\n[bold]Most recent raw stop event[/]")
                console.print_json(json.dumps(sample.raw)[:20000])


@app.command("quota")
def quota_command() -> None:
    """Show today's API usage. TfNSW gives no way to query this, so it's our own log."""
    _setup_logging()
    init_db()
    settings = get_settings()
    day = quota_day(now_utc(), settings.quota_reset_tz)

    table = Table(title=f"TfNSW API calls for quota day {day} ({settings.quota_reset_tz})")
    table.add_column("Calls", justify="right")
    table.add_column("Limit", justify="right")
    table.add_column("Used", justify="right")
    with session_scope() as session:
        used = calls_used(session, "tfnsw", day)
    table.add_row(str(used), str(settings.daily_quota), f"{used / settings.daily_quota * 100:.1f}%")
    console.print(table)


@app.command("schedule")
def schedule_command(
    stop: str = typer.Option("all", help="Watched stop key, or 'all'"),
) -> None:
    """Run the sampling loop until interrupted."""
    _setup_logging()
    init_db()
    stops = _select_stops(stop)
    bundles = {feed: ensure_bundle(feed) for feed in get_settings().gtfs_feeds}
    try:
        scheduling.run(stops, Timetables(bundles, stops))
    except KeyboardInterrupt:
        console.print("\n[yellow]stopped[/]")


@app.command("serve")
def serve_command(
    host: str = typer.Option("0.0.0.0", help="Bind address"),
    port: int = typer.Option(8000),
) -> None:
    """Serve the optional ground-truth ingest endpoint for the iOS Shortcuts."""
    import uvicorn

    _setup_logging()
    init_db()
    if not get_settings().ingest_token:
        console.print("[red]NEXTSTOP_INGEST_TOKEN is not set[/] — the endpoint will reject writes.")
    uvicorn.run("nextstop_collector.api:app", host=host, port=port)


@app.command("report")
def report_command(
    output: Path = typer.Option(Path("../docs/findings"), help="Output directory"),
) -> None:
    """Build the Phase 0 findings report from collected samples."""
    _setup_logging()
    init_db()
    from .report import build_report

    path = build_report(output)
    console.print(f"[green]report written[/] to {path.resolve()}")


@app.command("shortcut")
def shortcut_command(base_url: str = typer.Option("http://YOUR_VPS:8000")) -> None:
    """Print how to build the two optional iOS Shortcuts that capture ground truth."""
    token = get_settings().ingest_token or "<NEXTSTOP_INGEST_TOKEN>"
    known = ", ".join(BY_KEY)
    console.print(f"""
[bold]Optional.[/] The headline result comes from TfNSW's own realtime feed. These
Shortcuts add proof that the realtime estimate matched reality, not just the timetable.

Build two, one per event. Shortcuts app -> new shortcut -> "Get Contents of URL":
  URL     {base_url}/observations
  Method  POST
  Headers X-NextStop-Token = {token}
          Content-Type     = application/json
  Body    (JSON)
            event    = boarded   [dim](or "arrived" in the second shortcut)[/]
            corridor = chatswood [dim](one of: {known})[/]

Then "Add to Home Screen" so it is one tap. Verify with:
  curl -X POST {base_url}/observations \\
       -H "X-NextStop-Token: {token}" -H "Content-Type: application/json" \\
       -d '{{"event":"boarded","corridor":"chatswood"}}'
""")


@app.command("observe")
def observe_command(
    event: str = typer.Argument(help="boarded or arrived"),
    corridor: str = typer.Option(..., help=f"Journey label, e.g. one of: {', '.join(BY_KEY)}"),
    at: str | None = typer.Option(
        None, help="Sydney local time as 'YYYY-MM-DD HH:MM'. Defaults to now."
    ),
    note: str | None = typer.Option(None, help="Anything worth remembering about the trip"),
) -> None:
    """Record a board or arrival by hand, without running the HTTP endpoint.

    The Shortcuts route needs a public HTTPS server. For a dozen trips written down on a
    phone, this is the whole of the infrastructure.
    """
    if event not in ("boarded", "arrived"):
        raise typer.BadParameter("event must be 'boarded' or 'arrived'")

    if at is None:
        moment = now_utc()
    else:
        try:
            naive = datetime.strptime(at, "%Y-%m-%d %H:%M")
        except ValueError:
            raise typer.BadParameter("--at must look like '2026-07-28 09:03'") from None
        moment = naive.replace(tzinfo=ZoneInfo("Australia/Sydney"))

    init_db()
    with session_scope() as session:
        observation = Observation(
            recorded_at=moment, event=event, corridor=corridor, note=note
        )
        session.add(observation)
        session.flush()
        local = to_sydney(observation.recorded_at).strftime("%Y-%m-%d %H:%M %Z")
        console.print(f"[green]recorded[/] {event} on {corridor} at {local}")


def main() -> None:
    """Entry point that reports expected setup problems without a traceback.

    Anything other than these is a real bug and keeps its stack trace.
    """
    import sys

    try:
        app()
    except (FileNotFoundError, RuntimeError) as exc:
        console.print(f"[red]{exc}[/]")
        sys.exit(1)


if __name__ == "__main__":
    main()
