# Phase 1 — Live Activity spike

Answers one question before any of NextStop gets built on top of the assumption:

> Does the app keep running, and the Live Activity keep updating, while the phone is
> locked and CoreLocation is receiving **no fixes** — as happens for the whole Metro
> tunnel between Chatswood and Central?

The standard navigation-app trick holds a location session to stay alive. Underground
there are no location events arriving. If iOS suspends the process when that stream goes
quiet, the Live Activity freezes exactly where it is needed most. Nothing in Apple's
documentation settles this. Only a device test does.

## Why it is built as an instrument

Every device test costs a build plus TestFlight processing — roughly 20 minutes, with no
way around it, because the build machine is remote and the phone can never be plugged
into it. So one build runs several experiments, switched on-screen:

| Mechanism | What it tests |
| --- | --- |
| `CLBackgroundActivitySession` | The modern iOS 17+ API. Works with When In Use. |
| `CLLocationManager` updates | The classic `allowsBackgroundLocationUpdates` approach. |
| None | Control. Without it you cannot tell a working mechanism from an OS that simply had not suspended you yet. |

Tick interval is switchable too (1s / 5s / 15s).

## Reading the result

The Lock Screen shows **max gap** — the longest interval between consecutive ticks —
in green under 15s and red over. That is the entire verdict, readable at USyd without
unlocking the phone.

The log is the evidence. `Sources/App/SpikeLog.swift` appends to the App Group container
and flushes every line, because the case worth capturing is the process being suspended
without warning and a buffered line is a lost line. Read it on the Log tab, share it off
the device with the share sheet.

Lines worth finding:

| Line | Meaning |
| --- | --- |
| `gap` | A tick was missed. The number is how long. |
| `scene.background` | The moment the experiment actually starts. |
| `location.paused` | iOS paused location updates — usually followed by a gap. |
| `activity.state` | The system changed or culled the Live Activity. |
| `activity.payload.large` | Content state approaching the 4 KB limit, which fails silently. |

## Building

The project file is generated, never committed. XcodeGen builds it from `project.yml`.

```bash
cd ios
cp Signing.example.xcconfig Signing.xcconfig
xcodegen generate
open NextStop.xcodeproj
```

**Simulator builds need no Apple Developer account** — they are unsigned. Leave
`DEVELOPMENT_TEAM` empty in `Signing.xcconfig` and the whole thing compiles and runs.
Fill the Team ID in only when building for a real device.

The simulator will not answer the actual question: it cannot be locked, pocketed, or
taken through a tunnel. It only proves the code compiles and the layouts render.

## Sequence

| Stage | Where | Needs Apple account |
| --- | --- | --- |
| A. Write the code | Windows | no |
| B. Compile, fix errors, run in simulator | Codemagic `compile-check`, or a rented Mac | no |
| C. Sign, TestFlight, ride the Metro | Codemagic `testflight` | yes |

Stage B has two routes. Codemagic's `compile-check` workflow is free and needs no
account, but each iteration is ~10 minutes and it requires the repo to be pushed to a
git host. A rented Scaleway M1 (~€0.11/h, 24h minimum) turns that into a ~40 second
loop and needs no git remote — worth it if the first build throws a stack of errors,
which a fresh two-target project usually does.

## Test procedure

1. Open the app, Spike tab. Pick a mechanism. Leave the interval at 5s.
2. Tap **Start** and grant location access when prompted.
3. Lock the phone, pocket it, travel Chatswood → USyd.
4. On arrival, glance at the Lock Screen: max gap in green is a pass.
5. Open the app, Log tab, share the log.
6. Repeat with the next mechanism. The control run should fail — if it does not, the
   phone was never suspended and the other runs proved nothing.

## Scope

No routing, no map, no TfNSW calls, no styling. Everything else is Phase 2 and would
only add ways for this test to fail for uninteresting reasons.
