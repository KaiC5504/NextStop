import json
import logging
from pathlib import Path

import typer
from rich.console import Console
from rich.logging import RichHandler
from rich.table import Table

from . import collect as collect_module
from . import scheduling
from .config import get_settings
from .corridors import CORRIDORS, BY_KEY
from .quota import calls_used
from .storage.db import init_db, session_scope
from .tfnsw import stops as tfnsw_stops
from .tfnsw.client import TfnswClient
from .timeutil import now_sydney, now_utc, quota_day

app = typer.Typer(help="NextStop Phase 0 collector", no_args_is_help=True)
console = Console()


def _setup_logging(verbose: bool = False) -> None:
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(message)s",
        datefmt="%H:%M:%S",
        handlers=[RichHandler(console=console, rich_tracebacks=True, show_path=False)],
    )


def _corridor_keys(corridor: str) -> list[str]:
    if corridor == "all":
        return [c.key for c in CORRIDORS]
    if corridor not in BY_KEY:
        raise typer.BadParameter(f"unknown corridor {corridor!r}; known: {', '.join(BY_KEY)}, all")
    return [corridor]


@app.command("init-db")
def init_db_command() -> None:
    """Create the SQLite schema."""
    _setup_logging()
    init_db()
    console.print(f"[green]schema ready[/] at {get_settings().database_url}")


@app.command("resolve-stops")
def resolve_stops_command(
    output: Path = typer.Option(tfnsw_stops.DEFAULT_CACHE, help="Where to write stops.json"),
) -> None:
    """Look up stop IDs for every corridor endpoint and write them for you to check."""
    _setup_logging()
    init_db()
    with TfnswClient() as client:
        resolved = tfnsw_stops.resolve_all(client)
    tfnsw_stops.save(resolved, output)

    table = Table(title="Resolved stops — confirm these before collecting a week of data")
    table.add_column("Search")
    table.add_column("Chosen ID")
    table.add_column("Chosen name")
    table.add_column("Other candidates")
    for query, entry in resolved.items():
        others = ", ".join(c["name"] or "?" for c in entry["candidates"][1:4]) or "-"
        table.add_row(query, entry["chosen_id"] or "[red]none[/]", entry["chosen_name"] or "-", others)
    console.print(table)
    console.print(f"\nWritten to [bold]{output}[/]. Edit chosen_id by hand if one looks wrong.")


@app.command("collect-once")
def collect_once_command(
    corridor: str = typer.Option("all", help="Corridor key, or 'all'"),
    google: bool = typer.Option(True, help="Also query the Google Routes API"),
    alerts: bool = typer.Option(False, help="Also snapshot service alerts"),
    raw: bool = typer.Option(False, help="Print the raw response for fixture capture"),
) -> None:
    """Run a single collection pass now."""
    _setup_logging()
    init_db()
    keys = _corridor_keys(corridor)
    results = collect_module.collect_once(
        keys, when=now_sydney(), include_google=google, include_alerts=alerts
    )

    table = Table(title="Collection results")
    table.add_column("Provider")
    table.add_column("Corridor")
    table.add_column("Journeys", justify="right")
    table.add_column("Status")
    for result in results:
        table.add_row(
            result.provider,
            result.corridor,
            str(result.journey_count),
            "[green]ok[/]" if result.ok else f"[red]{result.error[:60]}[/]",
        )
    console.print(table)

    if raw:
        from .storage.models import TripQuery

        with session_scope() as session:
            for result in results:
                if result.query_id is None:
                    continue
                query = session.get(TripQuery, result.query_id)
                if query and query.raw_response:
                    console.print(f"\n[bold]{result.provider} / {result.corridor}[/]")
                    console.print_json(json.dumps(query.raw_response)[:20000])


@app.command("quota")
def quota_command() -> None:
    """Show today's API usage. TfNSW gives no way to query this, so it's our own log."""
    _setup_logging()
    init_db()
    settings = get_settings()
    day = quota_day(now_utc(), settings.quota_reset_tz)

    table = Table(title=f"API calls for quota day {day} ({settings.quota_reset_tz})")
    table.add_column("Provider")
    table.add_column("Calls", justify="right")
    table.add_column("Limit", justify="right")
    table.add_column("Used", justify="right")
    with session_scope() as session:
        for provider, limit in (("tfnsw", settings.daily_quota), ("google", None)):
            used = calls_used(session, provider, day)
            pct = f"{used / limit * 100:.1f}%" if limit else "-"
            table.add_row(provider, str(used), str(limit) if limit else "-", pct)
    console.print(table)


@app.command("schedule")
def schedule_command(
    corridor: str = typer.Option("all", help="Corridor key, or 'all'"),
    google: bool = typer.Option(True, help="Also query the Google Routes API"),
) -> None:
    """Run the polling loop until interrupted."""
    _setup_logging()
    init_db()
    try:
        scheduling.run(_corridor_keys(corridor), include_google=google)
    except KeyboardInterrupt:
        console.print("\n[yellow]stopped[/]")


@app.command("serve")
def serve_command(
    host: str = typer.Option("0.0.0.0", help="Bind address"),
    port: int = typer.Option(8000),
) -> None:
    """Serve the ground-truth ingest endpoint for the iOS Shortcuts."""
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
    """Build the Phase 0 findings report from collected data."""
    _setup_logging()
    init_db()
    from .report import build_report

    path = build_report(output)
    console.print(f"[green]report written[/] to {path.resolve()}")


@app.command("shortcut")
def shortcut_command(base_url: str = typer.Option("http://YOUR_VPS:8000")) -> None:
    """Print how to build the two iOS Shortcuts that capture ground truth."""
    settings = get_settings()
    token = settings.ingest_token or "<NEXTSTOP_INGEST_TOKEN>"
    console.print(f"""
[bold]Build two Shortcuts, one per event.[/]

For each: Shortcuts app -> new shortcut -> "Get Contents of URL":
  URL     {base_url}/observations
  Method  POST
  Headers X-NextStop-Token = {token}
          Content-Type     = application/json
  Body    (JSON)
            event    = boarded        [dim](or "arrived" in the second shortcut)[/]
            corridor = chatswood-usyd [dim](whichever you are travelling)[/]

Then "Add to Home Screen" so it is one tap. Verify with:
  curl -X POST {base_url}/observations \\
       -H "X-NextStop-Token: {token}" -H "Content-Type: application/json" \\
       -d '{{"event":"boarded","corridor":"chatswood-usyd"}}'
""")


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
