# Deploying the collector to the Hetzner VPS

Two systemd timers: one samples departures every 15 minutes, one keeps the stored
timetable current. Neither needs a process left running, so a reboot costs nothing and
a crash affects one sample rather than the whole week.

## Why timers rather than `nextstop schedule`

`schedule` still works and is fine for a laptop. Timers are better unattended: systemd
restarts them, `Persistent=true` catches up a run missed while the box was down, and
there is no long-lived process to leak memory over a week.

This only became practical once timetables were persisted to SQLite. Parsing the 99 MB
bus bundle takes ~40 seconds, so a scheduled task that re-parsed on every run would have
burned 40 seconds every 15 minutes. Now it is parsed once per service day and each
sample starts in about 1.7 seconds.

## Host timezone does not matter

Do not bother setting the VPS to Sydney time. The quota day, the commute window and GTFS
service days are all computed in `Australia/Sydney` inside the collector regardless of
the host clock. The timers are deliberately interval-based (`*:0/15`, `hourly`) rather
than pinned to a wall-clock hour, so no timezone appears in any unit file.

## Steps

```bash
# 1. Get the code onto the box (from Windows, in the repo root)
#    Either push to a git remote and clone, or copy directly:
scp -r . youruser@your-vps:~/NextStop

# 2. On the VPS
ssh youruser@your-vps
curl -LsSf https://astral.sh/uv/install.sh | sh     # if uv is not installed
cd ~/NextStop/collector
uv sync

# 3. Secrets. .env is not in git and must never be. Either scp your local one or
#    create it here. If you copy it from Windows, strip CRLF: systemd's
#    EnvironmentFile passes a trailing \r straight into the value, and the result
#    is a 401 that looks exactly like a wrong key.
cp .env.example .env
nano .env            # paste NEXTSTOP_TFNSW_API_KEY
sed -i 's/\r$//' .env
chmod 600 .env
grep '^NEXTSTOP_TFNSW_API_KEY=' .env | cat -A | tail -c 4   # must end in $, not ^M$

# 4. First build and a manual check before automating anything
uv run nextstop init-db
uv run nextstop gtfs-refresh        # confirm every bundle says "Today: yes"
uv run nextstop resolve-stops       # confirm the stop table looks right
uv run nextstop build-timetable
uv run nextstop collect-once        # should take ~2s and match most departures

# 5. Install the timers
mkdir -p ~/.config/systemd/user
cp ~/NextStop/deploy/*.service ~/NextStop/deploy/*.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now nextstop-timetable.timer nextstop-collect.timer

# 6. Let the units keep running after you log out
loginctl enable-linger $USER
```

`enable-linger` is not optional. Without it systemd stops user units when the last
session closes, and collection would end the moment you disconnect.

## Observed on the Hetzner Singapore box (Ubuntu 24.04, 2026-07-28)

| Step | Time |
| --- | --- |
| `gtfs-refresh` (all three bundles, ~111 MB) | 8s |
| `build-timetable` cold | 20s |
| `collect-once` warm | 2.2s |
| One timer run, CPU consumed | 1.3s |

The host clock is UTC+8 and is deliberately left that way — see §5.3 of the brief.

## Checking on it

```bash
systemctl --user list-timers 'nextstop*'
journalctl --user -u nextstop-collect.service -n 50
cd ~/NextStop/collector && uv run nextstop quota
```

A healthy sample logs `4/4 stops ok` with most departures matched. If matches drop to
zero, the timetable has gone stale — `uv run nextstop gtfs-refresh --force` and check
the coverage column.

## Getting the data back

The SQLite file lives at `~/NextStop/collector/nextstop.db`. Either build the report on
the VPS and copy the output, or pull the database down and report locally. Copy it under
a different name — `nextstop.db` locally is a scratch database from development, and
overwriting it loses nothing but confuses the next person to look:

```bash
scp KaiCVPS:~/NextStop/collector/nextstop.db ./collector/vps.db
cd collector && NEXTSTOP_DATABASE_URL=sqlite:///vps.db uv run nextstop report
```

## Ground truth (optional, and the only arm that proves correctness)

Everything above measures whether the realtime feed *disagrees* with the timetable.
Nothing in it shows which one was right. That takes a human on a platform, so it is two
iOS Shortcuts posting a timestamp — one "Boarded", one "Arrived".

`nextstop-api.service` is a long-running server rather than a timer. Install it the same
way as the others, then:

```bash
systemctl --user enable --now nextstop-api.service
curl -s localhost:8000/health
```

It binds to **127.0.0.1**, so it is not reachable from a phone until it is fronted by a
reverse proxy with a certificate. The endpoint authenticates with a token in a plain
header, and publishing that over `http://` puts the token on the open internet in
cleartext. With Caddy that is one line:

```
nextstop.example.com {
    reverse_proxy 127.0.0.1:8000
}
```

Then `uv run nextstop shortcut --base-url https://nextstop.example.com` prints the two
Shortcuts to build. Verify end to end with the `curl` it prints, and check the row
arrived with `GET /observations/recent`.
