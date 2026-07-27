# NextStop collector (Phase 0)

Answers the question Phase 0 exists to answer: **is the accuracy gap between the TfNSW
Trip Planner and Google Maps real, and which one matches what actually happens?**

Runs entirely on Windows. No Mac, no Apple Developer account, no iOS app.

## Setup

```bash
cd collector
cp .env.example .env      # then fill in the keys
uv sync
uv run nextstop init-db
```

You need two keys in `.env`:

- `NEXTSTOP_TFNSW_API_KEY` — from opendata.transport.nsw.gov.au, Applications →
  Create Application. Subscribe it to **Trip Planner** at minimum.
- `NEXTSTOP_GOOGLE_API_KEY` — Google Cloud project with billing enabled and the
  **Routes API** turned on.

Also set `NEXTSTOP_INGEST_TOKEN` to any random string. It is the shared secret the iOS
Shortcuts use so the ground-truth endpoint isn't open to the internet.

`.env` is gitignored and must stay that way.

## First run

```bash
uv run nextstop resolve-stops
```

Looks up the stop IDs for each corridor endpoint and writes `stops.json`. **Read the
table it prints before going further** — if it picked the wrong "Central", every later
poll collects the wrong journey. Edit `chosen_id` in `stops.json` by hand to correct it.

```bash
uv run nextstop collect-once --corridor chatswood-usyd --raw
```

One live poll of both providers, with the raw response printed so it can be turned into
a test fixture. The parsers were written from the published API docs before a key
existed, so this first real response is what tightens them.

## Collecting

```bash
uv run nextstop schedule            # runs until Ctrl+C
uv run nextstop serve               # ground-truth endpoint, separate process
```

`schedule` polls every 5 minutes during weekday peak (07:00–10:00, 16:00–19:00 Sydney)
and hourly otherwise. All timing is computed in `Australia/Sydney` regardless of where
the process runs, so a VPS in another region behaves identically.

Roughly 400 TfNSW calls a day against a 60,000 allowance. The binding constraint is the
feed refresh rate (10–15s), not quota, which is why nothing polls faster.

## Ground truth

This is the part that makes the dataset evidence rather than a disagreement log.

```bash
uv run nextstop shortcut --base-url http://your-vps:8000
```

Prints how to build two iOS Shortcuts — "Boarded" and "Arrived" — that POST a timestamp.
Add them to your home screen so logging a journey is one tap.

## Checking and reporting

```bash
uv run nextstop quota    # TfNSW offers no quota API, so this reads our own call log
uv run nextstop report   # writes ../docs/findings/
```

The report states plainly when it lacks the data to draw a conclusion rather than
implying one.

## Tests

```bash
uv run pytest
```

Runs offline with no API key. The GTFS-Realtime quirk filters (`tfnsw/quirks.py`) are
tested against synthetic protobuf feeds — that module is the one that later ports to
Swift, so it is deliberately pure and has no HTTP or storage dependency.
