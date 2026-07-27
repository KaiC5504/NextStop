# NextStop collector (Phase 0)

Answers the question Phase 0 exists to answer: **does the published timetable alone
tell you when your train actually leaves?**

Every 15 minutes across the Chatswood commute window it records, for each watched stop:

- the **scheduled** departure time, from the static GTFS bundle — what a naive
  timetable app would display
- the **realtime** departure time, from the Trip Planner API — what is actually
  happening
- the **delta** between them

That delta is the thesis. It is the same gap that separates a good transit app from a
mediocre one, measured entirely within TfNSW's own data.

Runs on Windows. No Mac, no Apple Developer account, no iOS app.

## Setup

```bash
cd collector
cp .env.example .env      # then fill in NEXTSTOP_TFNSW_API_KEY
uv sync
uv run nextstop init-db
```

The one required key is `NEXTSTOP_TFNSW_API_KEY`, from
opendata.transport.nsw.gov.au → Applications → Create Application. Subscribe it to
**Trip Planner** and **Public Transport - Timetables** (the static GTFS bundles).

`.env` is gitignored and must stay that way.

## First run

```bash
uv run nextstop gtfs-refresh     # downloads the metro and sydneytrains bundles
uv run nextstop resolve-stops    # then READ the table it prints
```

`resolve-stops` maps each watched stop to a Trip Planner ID *and* a set of GTFS
`stop_id` values. These come from two different systems and are not assumed to match,
which is why both are written to `stops.json` for you to check. A wrong match here
silently poisons every later sample — if the collector later reports departures but
zero timetable matches, this file is the first place to look.

```bash
uv run nextstop collect-once --raw
```

One live sampling pass, printing a raw stop event so it can become a test fixture. The
parsers were written from the published API manual before a key existed, so this first
real response is what tightens them.

## Collecting

```bash
uv run nextstop schedule         # runs until Ctrl+C
```

Samples every 15 minutes on weekdays during 06:00–10:00 and 15:00–20:00 Sydney time,
and hourly outside that window. The off-peak baseline is deliberate: showing that
schedule and realtime agree when nothing is wrong is what makes the peak-hour gap
meaningful rather than just noise.

All timing is computed in `Australia/Sydney` regardless of where the process runs, so a
VPS in another region behaves identically. Roughly 190 calls a day against a 60,000
allowance — quota is nowhere near the constraint.

The same departure is sampled repeatedly as it approaches. That is intentional: watching
an estimate move shows whether the Trip Planner predicts a delay or only reports it.

## Reporting

```bash
uv run nextstop quota    # TfNSW offers no quota API, so this reads our own call log
uv run nextstop report   # writes ../docs/findings/
```

The report distinguishes two measures on purpose:

- **api_delay** — realtime minus planned, both from one Trip Planner response. Always
  available, never depends on a join. The robust headline.
- **naive_gap** — realtime minus the *static GTFS* time. What a timetable-only app
  would get wrong. Null when the static match fails, and the match rate is reported
  rather than hidden.

It states plainly when it lacks the data to draw a conclusion.

## Ground truth (optional)

```bash
uv run nextstop serve
uv run nextstop shortcut --base-url http://your-vps:8000
```

Two home-screen Shortcuts that POST a timestamp when you board and arrive. Not needed
for the headline result, which comes from TfNSW's own feed. It adds the stronger claim:
that the realtime estimate matched reality, not merely that it differed from the
timetable.

## Tests

```bash
uv run pytest
```

83 tests, all offline, no API key needed. Worth knowing what they cover:

- `tfnsw/quirks.py` — the GTFS-Realtime filters from brief §4, tested against synthetic
  protobuf feeds. Pure, with no HTTP or storage dependency, because this is the module
  that later ports to Swift.
- `gtfs/static.py` — timetable parsing against a synthetic bundle, including the
  daylight-saving case where a naive midnight anchor shifts every departure by an hour.
- `storage/models.py` — UTC round trips, because SQLite silently drops tzinfo.

`journeys.py` and `tfnsw/trip.py` are not used by Phase 0. They parse the `trip`
endpoint and are kept for Phase 2 (R1), where routing is the whole point.
