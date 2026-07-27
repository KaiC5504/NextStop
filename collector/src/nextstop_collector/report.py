"""Turn collected data into the Phase 0 finding: is the accuracy gap real?

Three questions, in increasing order of what they prove:
  1. Do the two providers disagree, and by how much?
  2. When they disagree, which one matched what actually happened?
  3. Does either reflect disruptions that were published at the time?

Only (2) is evidence. It needs ground-truth observations, so a report built from API
data alone says so rather than implying more than it knows.
"""

from datetime import timedelta
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt  # noqa: E402
import pandas as pd  # noqa: E402
from sqlalchemy import select  # noqa: E402

from .storage.db import session_scope  # noqa: E402
from .storage.models import Observation, ServiceAlert, TripOption, TripQuery  # noqa: E402

MATCH_WINDOW = timedelta(minutes=3)
GROUND_TRUTH_LOOKBACK = timedelta(minutes=30)


def load_best_options() -> pd.DataFrame:
    """Highest-ranked journey from every successful query, one row each."""
    with session_scope() as session:
        rows = session.execute(
            select(
                TripQuery.id,
                TripQuery.provider,
                TripQuery.corridor,
                TripQuery.requested_at,
                TripOption.departure_time,
                TripOption.arrival_time,
                TripOption.duration_seconds,
                TripOption.is_realtime,
                TripOption.mode_sequence,
            )
            .join(TripOption, TripOption.query_id == TripQuery.id)
            .where(TripOption.rank == 0)
        ).all()

    frame = pd.DataFrame(rows, columns=[
        "query_id", "provider", "corridor", "requested_at",
        "departure_time", "arrival_time", "duration_seconds",
        "is_realtime", "mode_sequence",
    ])
    for column in ("requested_at", "departure_time", "arrival_time"):
        if not frame.empty:
            frame[column] = pd.to_datetime(frame[column], utc=True)
    return frame


def load_observations() -> pd.DataFrame:
    with session_scope() as session:
        rows = session.execute(
            select(Observation.recorded_at, Observation.event, Observation.corridor)
        ).all()
    frame = pd.DataFrame(rows, columns=["recorded_at", "event", "corridor"])
    if not frame.empty:
        frame["recorded_at"] = pd.to_datetime(frame["recorded_at"], utc=True)
    return frame


def pair_providers(options: pd.DataFrame) -> pd.DataFrame:
    """Match each TfNSW query to the Google query for the same corridor at the same moment."""
    if options.empty:
        return pd.DataFrame()

    tfnsw = options[options.provider == "tfnsw"].sort_values("requested_at")
    google = options[options.provider == "google"].sort_values("requested_at")
    if tfnsw.empty or google.empty:
        return pd.DataFrame()

    merged = pd.merge_asof(
        tfnsw,
        google,
        on="requested_at",
        by="corridor",
        tolerance=MATCH_WINDOW,
        direction="nearest",
        suffixes=("_tfnsw", "_google"),
    ).dropna(subset=["departure_time_google"])

    merged["departure_delta_min"] = (
        merged.departure_time_tfnsw - merged.departure_time_google
    ).dt.total_seconds() / 60
    merged["duration_delta_min"] = (
        merged.duration_seconds_tfnsw - merged.duration_seconds_google
    ) / 60
    return merged


def score_against_truth(options: pd.DataFrame, observations: pd.DataFrame) -> pd.DataFrame:
    """For each boarding, how wrong was each provider's predicted departure?"""
    if options.empty or observations.empty:
        return pd.DataFrame()

    boardings = observations[observations.event == "boarded"]
    if boardings.empty:
        return pd.DataFrame()

    records = []
    for _, boarding in boardings.iterrows():
        window_start = boarding.recorded_at - GROUND_TRUTH_LOOKBACK
        for provider in ("tfnsw", "google"):
            candidates = options[
                (options.provider == provider)
                & (options.corridor == boarding.corridor)
                & (options.requested_at <= boarding.recorded_at)
                & (options.requested_at >= window_start)
            ]
            if candidates.empty:
                continue
            latest = candidates.sort_values("requested_at").iloc[-1]
            if pd.isna(latest.departure_time):
                continue
            records.append({
                "corridor": boarding.corridor,
                "boarded_at": boarding.recorded_at,
                "provider": provider,
                "predicted_departure": latest.departure_time,
                "error_minutes": (
                    latest.departure_time - boarding.recorded_at
                ).total_seconds() / 60,
            })
    return pd.DataFrame(records)


def _plot_disagreement(paired: pd.DataFrame, path: Path) -> bool:
    if paired.empty:
        return False
    fig, axes = plt.subplots(1, 2, figsize=(11, 4))
    axes[0].hist(paired.departure_delta_min.dropna(), bins=30, color="#4C72B0")
    axes[0].set_title("Departure: TfNSW minus Google")
    axes[0].set_xlabel("minutes")
    axes[1].hist(paired.duration_delta_min.dropna(), bins=30, color="#DD8452")
    axes[1].set_title("Duration: TfNSW minus Google")
    axes[1].set_xlabel("minutes")
    for ax in axes:
        ax.axvline(0, color="black", linewidth=1, linestyle="--")
        ax.set_ylabel("polls")
    fig.tight_layout()
    fig.savefig(path, dpi=140)
    plt.close(fig)
    return True


def _plot_accuracy(scored: pd.DataFrame, path: Path) -> bool:
    if scored.empty:
        return False
    fig, ax = plt.subplots(figsize=(7, 4))
    for provider, colour in (("tfnsw", "#4C72B0"), ("google", "#DD8452")):
        subset = scored[scored.provider == provider].error_minutes
        if not subset.empty:
            ax.hist(subset, bins=20, alpha=0.6, label=provider, color=colour)
    ax.axvline(0, color="black", linewidth=1, linestyle="--")
    ax.set_title("Predicted departure minus actual boarding")
    ax.set_xlabel("minutes (positive = predicted later than reality)")
    ax.set_ylabel("boardings")
    ax.legend()
    fig.tight_layout()
    fig.savefig(path, dpi=140)
    plt.close(fig)
    return True


def _summarise_accuracy(scored: pd.DataFrame) -> str:
    if scored.empty:
        return (
            "No ground-truth observations collected yet, so this run cannot say which "
            "provider is more accurate — only whether they disagree. Tap the Boarded and "
            "Arrived Shortcuts on your commute to populate this section.\n"
        )
    lines = ["| Provider | Boardings | Mean abs. error (min) | Median error (min) | Within 2 min |",
             "| --- | ---: | ---: | ---: | ---: |"]
    for provider, group in scored.groupby("provider"):
        within = (group.error_minutes.abs() <= 2).mean() * 100
        lines.append(
            f"| {provider} | {len(group)} | {group.error_minutes.abs().mean():.1f} | "
            f"{group.error_minutes.median():.1f} | {within:.0f}% |"
        )
    return "\n".join(lines) + "\n"


def build_report(output_dir: Path) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    options = load_best_options()
    observations = load_observations()
    paired = pair_providers(options)
    scored = score_against_truth(options, observations)

    with session_scope() as session:
        alert_count = len(session.execute(select(ServiceAlert.id)).all())

    has_disagreement_chart = _plot_disagreement(paired, output_dir / "provider-disagreement.png")
    has_accuracy_chart = _plot_accuracy(scored, output_dir / "prediction-accuracy.png")

    realtime_note = "no TfNSW journeys collected yet"
    tfnsw_rows = options[options.provider == "tfnsw"] if not options.empty else pd.DataFrame()
    if not tfnsw_rows.empty:
        realtime_note = f"{tfnsw_rows.is_realtime.mean() * 100:.0f}% carried a realtime estimate"

    sections = [
        "# Phase 0 findings\n",
        "Generated by `nextstop report`. Regenerate any time — it reads only stored data.\n",
        "## Collection volume\n",
        f"- Trip queries stored: **{len(options)}** (best option per query)\n",
        f"- Ground-truth observations: **{len(observations)}**\n",
        f"- Service alert snapshots: **{alert_count}**\n",
        f"- TfNSW realtime coverage: {realtime_note}\n",
        "\n## Which provider was right?\n",
        _summarise_accuracy(scored),
    ]

    if has_accuracy_chart:
        sections.append("\n![Prediction accuracy](prediction-accuracy.png)\n")

    sections.append("\n## Do they disagree?\n")
    if paired.empty:
        sections.append(
            "Not enough paired polls yet. This needs both providers collecting the same "
            "corridor at the same time.\n"
        )
    else:
        sections.append(
            f"- Paired polls: **{len(paired)}**\n"
            f"- Median departure difference: **{paired.departure_delta_min.median():.1f} min**\n"
            f"- Polls differing by more than 2 min: "
            f"**{(paired.departure_delta_min.abs() > 2).mean() * 100:.0f}%**\n"
            f"- Median duration difference: **{paired.duration_delta_min.median():.1f} min**\n"
        )
    if has_disagreement_chart:
        sections.append("\n![Provider disagreement](provider-disagreement.png)\n")

    path = output_dir / "README.md"
    path.write_text("".join(sections), encoding="utf-8")
    return path
