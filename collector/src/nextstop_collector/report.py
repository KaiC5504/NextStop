"""Turn collected samples into the Phase 0 finding.

The claim under test: an app built on the published timetable alone is wrong often
enough to matter, and the Trip Planner's realtime feed catches it.

Two measures, and the difference between them is deliberate:

  api_delay   estimated minus planned, both from one Trip Planner response. Always
              available, never depends on a join. This is the robust headline.
  naive_gap   estimated minus the static GTFS scheduled time. This is what a naive
              consumer would get wrong. Null when the static match failed, and the
              match rate is reported rather than hidden.
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402
from sqlalchemy import select  # noqa: E402

from .storage.db import session_scope  # noqa: E402
from .storage.models import DepartureSample, Observation, ServiceAlert  # noqa: E402
from .timeutil import SYDNEY  # noqa: E402

LATE_THRESHOLD_SECONDS = 120


def load_samples() -> pd.DataFrame:
    with session_scope() as session:
        rows = session.execute(
            select(
                DepartureSample.polled_at,
                DepartureSample.stop_key,
                DepartureSample.route,
                DepartureSample.mode,
                DepartureSample.planned_departure,
                DepartureSample.estimated_departure,
                DepartureSample.scheduled_departure,
                DepartureSample.api_delay_seconds,
                DepartureSample.naive_gap_seconds,
                DepartureSample.planned_vs_scheduled_seconds,
                DepartureSample.matched_static,
            )
        ).all()

    frame = pd.DataFrame(
        rows,
        columns=[
            "polled_at", "stop_key", "route", "mode",
            "planned_departure", "estimated_departure", "scheduled_departure",
            "api_delay_seconds", "naive_gap_seconds", "planned_vs_scheduled_seconds",
            "matched_static",
        ],
    )
    if frame.empty:
        return frame

    for column in ("polled_at", "planned_departure", "estimated_departure", "scheduled_departure"):
        frame[column] = pd.to_datetime(frame[column], utc=True)

    frame["local_hour"] = frame.planned_departure.dt.tz_convert(SYDNEY).dt.hour
    frame["weekday"] = frame.planned_departure.dt.tz_convert(SYDNEY).dt.weekday
    frame["commute_window"] = frame.weekday.lt(5) & (
        frame.local_hour.between(6, 9) | frame.local_hour.between(15, 19)
    )
    frame["api_delay_min"] = frame.api_delay_seconds / 60
    frame["naive_gap_min"] = frame.naive_gap_seconds / 60
    return frame


def latest_view(frame: pd.DataFrame) -> pd.DataFrame:
    """One row per distinct departure — its final observed estimate.

    Each departure is sampled repeatedly as it approaches, so raw rows over-represent
    services that were visible for longer. Collapsing to the last reading per departure
    keeps the per-service statistics honest.
    """
    if frame.empty:
        return frame
    return (
        frame.sort_values("polled_at")
        .groupby(["stop_key", "route", "planned_departure"], as_index=False)
        .last()
    )


def _plot_delay(frame: pd.DataFrame, path: Path) -> bool:
    usable = frame.dropna(subset=["api_delay_min"])
    if usable.empty:
        return False

    has_gap = usable.naive_gap_min.notna().any()
    fig, axes = plt.subplots(1, 2 if has_gap else 1, figsize=(11 if has_gap else 6, 4), squeeze=False)

    axes[0][0].hist(usable.api_delay_min, bins=40, color="#4C72B0")
    axes[0][0].set_title("Realtime minus planned (Trip Planner)")
    axes[0][0].set_xlabel("minutes late")
    axes[0][0].set_ylabel("departures")
    axes[0][0].axvline(0, color="black", linewidth=1, linestyle="--")

    if has_gap:
        axes[0][1].hist(usable.naive_gap_min.dropna(), bins=40, color="#DD8452")
        axes[0][1].set_title("Realtime minus published timetable")
        axes[0][1].set_xlabel("minutes a naive app would be wrong by")
        axes[0][1].set_ylabel("departures")
        axes[0][1].axvline(0, color="black", linewidth=1, linestyle="--")

    fig.tight_layout()
    fig.savefig(path, dpi=140)
    plt.close(fig)
    return True


def _plot_by_hour(frame: pd.DataFrame, path: Path) -> bool:
    usable = frame.dropna(subset=["api_delay_min"])
    if usable.empty or usable.local_hour.nunique() < 2:
        return False
    grouped = usable.groupby("local_hour").api_delay_min.agg(["median", "count"])
    fig, ax = plt.subplots(figsize=(8, 4))
    ax.bar(grouped.index, grouped["median"], color="#4C72B0")
    ax.set_title("Median delay by hour of day (Sydney time)")
    ax.set_xlabel("hour")
    ax.set_ylabel("minutes")
    ax.axhline(0, color="black", linewidth=1)
    fig.tight_layout()
    fig.savefig(path, dpi=140)
    plt.close(fig)
    return True


def _delay_table(frame: pd.DataFrame) -> str:
    usable = frame.dropna(subset=["api_delay_min"])
    if usable.empty:
        return "_No departures carried a realtime estimate yet._\n"

    lines = [
        "| Sample | Departures | Median | 90th pct | Late by >2 min |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for label, subset in (
        ("All", usable),
        ("Commute window", usable[usable.commute_window]),
        ("Off-peak baseline", usable[~usable.commute_window]),
    ):
        if subset.empty:
            continue
        late = (subset.api_delay_seconds > LATE_THRESHOLD_SECONDS).mean() * 100
        lines.append(
            f"| {label} | {len(subset)} | {subset.api_delay_min.median():.1f} min | "
            f"{subset.api_delay_min.quantile(0.9):.1f} min | {late:.0f}% |"
        )
    return "\n".join(lines) + "\n"


def _naive_gap_section(frame: pd.DataFrame) -> str:
    matched = frame[frame.matched_static]
    if frame.empty:
        return ""
    match_rate = frame.matched_static.mean() * 100

    if matched.empty:
        return (
            f"Static timetable match rate: **{match_rate:.0f}%**. Nothing matched, so this "
            "section cannot be computed. That usually means the GTFS stop IDs in "
            "`stops.json` are wrong — check them against the names printed by "
            "`nextstop resolve-stops`.\n"
        )

    usable = matched.dropna(subset=["naive_gap_min"])
    if usable.empty:
        return f"Static timetable match rate: **{match_rate:.0f}%**, but none had a realtime estimate yet.\n"

    wrong = (usable.naive_gap_seconds.abs() > LATE_THRESHOLD_SECONDS).mean() * 100
    disagreement = matched.planned_vs_scheduled_seconds.abs().gt(60).mean() * 100
    return (
        f"- Static timetable match rate: **{match_rate:.0f}%** of departures\n"
        f"- Median gap between realtime and published timetable: "
        f"**{usable.naive_gap_min.median():.1f} min**\n"
        f"- Departures a timetable-only app would show wrong by more than 2 minutes: "
        f"**{wrong:.0f}%**\n"
        f"- Trip Planner's own \"planned\" time disagreeing with the published timetable "
        f"by more than 1 min: **{disagreement:.0f}%**\n"
    )


def build_report(output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    raw = load_samples()
    frame = latest_view(raw)

    with session_scope() as session:
        alert_count = len(session.execute(select(ServiceAlert.id)).all())
        observation_count = len(session.execute(select(Observation.id)).all())

    sections = [
        "# Phase 0 findings\n\n",
        "Does the published timetable alone tell you when your train leaves?\n\n",
        "Generated by `nextstop report` from stored samples only. Regenerate any time.\n\n",
        "## Collection volume\n\n",
        f"- Departure samples: **{len(raw)}**\n",
        f"- Distinct departures observed: **{len(frame)}**\n",
        f"- Service alert snapshots: **{alert_count}**\n",
        f"- Ground-truth observations: **{observation_count}**\n\n",
    ]

    if raw.empty:
        sections.append(
            "**No data collected yet.** This report is the empty-state output of a "
            "collector that has never run against the live API. Set `NEXTSTOP_TFNSW_API_KEY`, "
            "run `nextstop gtfs-refresh` and `nextstop resolve-stops`, then start "
            "`nextstop schedule`.\n"
        )
        path = output_dir / "README.md"
        path.write_text("".join(sections), encoding="utf-8")
        return path

    realtime_coverage = frame.estimated_departure.notna().mean() * 100
    sections += [
        "## How late do services actually run?\n\n",
        f"Realtime coverage: **{realtime_coverage:.0f}%** of departures carried a live estimate.\n\n",
        _delay_table(frame),
        "\n## What a timetable-only app would miss\n\n",
        _naive_gap_section(frame),
    ]

    if _plot_delay(frame, output_dir / "delay-distribution.png"):
        sections.append("\n![Delay distribution](delay-distribution.png)\n")
    if _plot_by_hour(frame, output_dir / "delay-by-hour.png"):
        sections.append("\n![Delay by hour](delay-by-hour.png)\n")

    path = output_dir / "README.md"
    path.write_text("".join(sections), encoding="utf-8")
    return path
