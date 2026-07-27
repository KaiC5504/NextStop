# PROJECT BRIEF — Sydney Transit App (working title: NextStop)

> Read this file before doing anything else. It defines what I'm building, the
> constraints I'm working under, and the decisions already made. If you're about
> to suggest something this document rules out, re-read the relevant section
> first. If you think a decision here is wrong, say so explicitly rather than
> quietly working around it.

---

## 1. What I'm building

An iOS 26 (or 27 in upcoming but I believe it would work for both) app for Sydney public transport that combines:

- the **routing and timing accuracy of the official Opal Travel app**, with
- the **map legibility and navigation feel of Google Maps**, plus
- **Live Activity support**, which neither Opal Travel nor Google Maps does well
for my use case.

This is a personal-use app first. If it works well it may become an open-source
project. It is **not** a commercial product and does not need App Store release.

### The problem it solves

Opal Travel is accurate but has no Live Activity or Dynamic Island support, and
its map is poor — I can't see where I'm going. Google Maps has a good map and a
Live Activity, but its transit data is less reliable, especially around delays,
trackwork and replacement services.

### Primary test route

Chatswood ↔ city / University of Sydney corridor, mostly Sydney Metro plus some
bus legs. Everything should be validated against real journeys on this corridor
before generalising.

---

## 2. Requirements

These are the acceptance criteria. Track them explicitly.


| #   | Requirement                                                                                 | Status      |
| --- | ------------------------------------------------------------------------------------------- | ----------- |
| R1  | Routing and departure times match Opal Travel, not Google's approximations                  | Phase 0 collector built and tested; blocked on TfNSW API key |
| R2  | A real map showing my route and current position, comparable to Google Maps                 | Not started |
| R3  | Live Activity on the Lock Screen **and** Dynamic Island for an active journey               | Mechanism identified (§5.1); unproven on device, gated on Apple enrolment |
| R4  | "Get off at the next stop" alert that fires reliably with the phone locked and in my pocket | Design revised to two mechanisms — see §5.2 |
| R5  | Correct handling of delays, disruptions, trackwork and replacement services                 | GTFS-R quirk filters written and unit-tested against synthetic feeds |


R3 and R4 are the whole reason this project exists. If they can't be made to work
reliably, the project isn't worth finishing — validate them early (see §7).

---

## 3. Hard constraints

Do not propose solutions that violate these.

- **I develop on Windows.** No Mac laptop, no Mac desktop.
- **I test on a physical iPhone.** No simulator access on Windows.
- **I am not writing the code.** You (Claude Code) write it. I run things,
test on device, and report back what happened. Explain what you're doing and
why, in a way I can follow and verify — don't just emit code silently.
- **Budget:** I will pay the Apple Developer Program fee (~USD $99/yr) and I'm
willing to **rent a cloud Mac** by the hour or day for building and testing.
I will not buy a Mac at this stage.
- **Latency:** I'm in Sydney. Rented Macs are in the US or EU. GUI/remote-desktop
work over that link is painful — prefer SSH + CLI workflows over anything that
needs Xcode's GUI.

---

## 4. Data sources

All data comes from the **Transport for NSW Open Data Hub**
(`https://opendata.transport.nsw.gov.au`). Free registration, API key in an
`Authorization` header.

### Primary: Trip Planner API

This is the key insight of the whole project. Opal Travel's accuracy isn't
proprietary — the Trip Planner API talks directly to the same `transportnsw.info`
trip planner engine that Opal Travel uses. **Use this for routing, not GTFS.**
Do not reimplement routing from static GTFS.

Endpoints: Stop Finder, Trip Planner, Departure, Service Alerts, Coordinate
Request.

### Secondary: GTFS-Realtime feeds

For live vehicle positions (the moving dot on the map) and stop time updates.
Protobuf format.

### Service alerts

The Service Alerts endpoint carries incident data published from TfNSW's
Incident Capture System — this is what gives us R5 and what Google handles badly.

### Known quirks — handle these explicitly, they are the reason Google gets it wrong

These quirks all belong to the **GTFS-Realtime** layer, not the Trip Planner JSON API.
Trip Planner drives R1; these drive R5. Implemented and unit-tested in
`collector/src/nextstop_collector/tfnsw/quirks.py`, which is pure and ports to Swift.

- **Non-standard GTFS-R:** `REPLACEMENT` was removed from the official
GTFS-realtime spec but the Sydney Trains feed still contains it. Replacement/altered
services are exactly the delay and trackwork cases we care about.
**Corrected 2026-07-27:** the official Python bindings *do* still define
`REPLACEMENT = 5`, so it parses cleanly — the brief's "generic parsers mishandle
this" overstates it. The real failure mode is downstream code that switches on
`schedule_relationship` with no `REPLACEMENT` branch and silently treats these as
ordinary scheduled services. Hence `classify_trip()` names them explicitly rather
than letting them fall through a default.
- **Non-revenue services:** exclude any service with `route_id` of `RTTA_DEF`
or `RTTA_REV`. Also exclude Sydney Trains charter services. These must never
be shown to a user.
- **Duplicate services:** the NSW Trains and Sydney Trains feeds overlap.
Filter or you'll show the same train twice.
- **Passing stops:** the Sydney Trains feed includes stops flagged
no-set-down / no-pick-up. Don't display these as boardable.
- **Trackwork:** replacement bus services live in a separate fileset. Handle
separately or trackwork will silently not appear.

### Rate limits

- Default "Bronze" plan: **60,000 calls/day, 5 calls/second.**
- Quota counter **resets at midnight AEST**. I may run collection jobs from a
VPS in Singapore (UTC+8), so midnight AEST = 22:00 Singapore. Mind the offset.
**Note 2026-07-27:** "midnight AEST" is ambiguous — AEST is fixed UTC+10 but Sydney
shifts to UTC+11 over summer, so the two readings differ by an hour for half the
year. The collector assumes the colloquial reading (Sydney local midnight) and makes
it configurable rather than silently picking one; at our volume the distinction is
immaterial. The offset problem is sidestepped entirely by computing every schedule
and quota decision in `Australia/Sydney` regardless of host timezone.
- **There is no API to check your own quota usage.** Log it yourself. Done — every
attempt, including retries, lands in the `api_call_log` table; `nextstop quota` reads it.
- Real-time files only refresh every **10–15 seconds**. TfNSW explicitly
recommends polling every 15s and says faster is pointless. At 15s that's
~5,760 calls/day per feed — comfortably within quota.
- Intermittent HTTP 503 "quota or rate limit exceeded" responses are known to
occur well under the documented limits. **Build retry with exponential
backoff from day one.**

---

## 5. Architecture decisions

### 5.1 Live Activity updates: prefer on-device, not push

Apple meters push-driven Live Activity updates via an **ActivityKit notification
budget**. Priority-10 pushes draw down the budget; priority-5 pushes don't.
Apple engineers have stated plainly that updating every few seconds at high
priority exhausts the budget and remaining pushes are silently dropped — even
with `NSSupportsLiveActivitiesFrequentUpdates` enabled.

**Decision:** during an active journey the app already holds background location,
so update the Live Activity **locally on-device**. No APNs, no budget, no
throttling. Reserve push notifications for disruption alerts only.

**Confirmed 2026-07-27.** With `UIBackgroundModes: location` active the app process
stays alive and can call `Activity.update()` as often as it likes — no push, no budget,
no throttling. This is the standard navigation-app pattern. It is however *not*
documented by Apple as a guarantee, which is what Phase 1 exists to prove on device.

Known ActivityKit limits: 8 hours active, a further 4 hours persisting on the Lock
Screen, and a 4 KB content-state ceiling that iOS 26 fails **silently** when exceeded.
A commute fits comfortably; the silent failure mode is worth remembering when the
content state grows.

### 5.2 Hop-off alerts: two mechanisms, not one

**Revised 2026-07-27.** The original design — region monitoring alone — fails on the
primary test route. Region monitoring needs location fixes, and Chatswood→Sydenham is
tunnel for most of the commute. Mobile *data* works in Sydney Metro tunnels, but that
does not give CoreLocation a usable fix. A geofence-only R4 would be least reliable
exactly where it is needed most.

Three layers, in order of how much they can be trusted:

1. **Pre-scheduled local notification (the floor).** Compute the alighting time from
the Trip Planner ETA and schedule a `UNNotificationRequest` for shortly before it.
Re-arm whenever the app gets execution time. This fires with the phone locked
regardless of GPS, connectivity, or whether the app is running. Everything else is
an optimisation on top of this.
2. **Region monitoring (precision).** Geofence the alighting stop for surface stops
and above-ground legs, where a fix is actually available. Still the right primitive
where it works — it wakes a suspended app.
3. **Feed-derived correction.** While background location holds the process alive
(§5.1), correct the predicted arrival from GTFS-R stop time updates over mobile data.

Do **not** build any of this on foreground polling.

### 5.2.1 Why not just push notifications for the alert

Same reason as §5.1 — this has to work when the network is bad, and a locally scheduled
notification has no delivery dependency at all.

### 5.3 No backend required for the core app

The phone calls the Trip Planner API directly. A server is only needed if we end
up requiring APNs push updates (§5.1) or for offline data collection (§7,
Phase 0). I have a Hetzner VPS available if needed.

### 5.4 Stack: DECIDED — native Swift

**Resolved 2026-07-27, before Phase 1 rather than during it.** The bake-off was
cancelled because the decision turned out to follow from §5.1 rather than needing
evidence.

`expo-widgets` is real and genuinely first-party (Expo SDK 57) — the original brief was
right about that. But Expo's own documentation states the only background update path
is **APNs push**. §5.1 chose local on-device updates specifically to avoid the
notification budget, and §9 rules out high-frequency push. Option A therefore cannot
deliver the architecture already decided; taking it would mean reversing §5.1.

Two things reinforce it:

- R4 needs a `CLLocationManager` delegate reached while the app is suspended. That is
Swift either way — Option A means writing the same Swift plus an RN bridge, and
blind-debugging two layers instead of one.
- iOS 26's Liquid Glass (`glassEffect`, `GlassEffectContainer`, `glassEffectID`) is
SwiftUI-only, and is the look this app wants.

**Accepted cost:** no SwiftUI previews from Windows. Mitigated by building an in-app
layout harness — a debug screen rendering all five Live Activity presentations (Lock
Screen, Dynamic Island compact leading/trailing, minimal, expanded) at real sizes
against mock state. Layout iteration happens by looking at the phone. Previews are also
available on the rented Mac over VNC when visual work genuinely needs them.

**Ruled out:** Xcode Cloud. Despite 25 free compute hours included with the
Developer Program, workflows must be configured *in Xcode*, which I don't have.

---

## 6. Development workflow

```
Windows (Claude Code writes)  →  git push  →  Codemagic (build + sign)  →  TestFlight  →  my iPhone
                                          ↘  rented Mac, for bring-up and debug sprints
```

**Revised 2026-07-27.** A rented Mac is no longer the default path, only the sprint
path. `codemagic.yaml` is plain text editable from Windows, the free tier is 500 M2
minutes/month, and it handles signing and TestFlight upload on push. Rent a Mac when
the CI round-trip is the bottleneck — notably initial bring-up, where blind-written
SwiftUI means a long run of compile errors and a 6–10 minute round trip per error is
intolerable.

**The real constraint is not compile time.** Every on-device test costs a build plus
TestFlight processing, roughly 15–30 minutes. Design for that: verbose on-device
logging and in-app harnesses beat round trips.

### Critical: use XcodeGen (or Tuist)

If we go native Swift, **do not commit an `.xcodeproj`.** Adding a single file
to an Xcode project means editing `project.pbxproj`, a dense machine-generated
format that cannot sanely be hand-edited from Windows.

Instead: define the project in a plain-text `project.yml`, generate the
`.xcodeproj` on the Mac, and gitignore it. Use wildcard patterns
(`Sources/**/*.swift`) so adding a file requires no project-file change at all.

- **XcodeGen** — YAML, simple, still maintained in 2026 though updates are
slower and community-driven. Preferred for a two-target app.
- **Tuist** — Swift DSL, more actively developed, more features. Overkill here.

`.gitignore` must include `*.xcodeproj`, `*.xcworkspace`, `DerivedData/`.

### Line endings

Add `.gitattributes` with `* text=auto eol=lf` **on day one**. Windows CRLF in
shell scripts breaks builds on macOS in confusing, hard-to-diagnose ways.

### Cloud Mac

Rented by the hour/day. Run Claude Code **on the Mac over SSH** for the
compile-fix loop — you see your own `xcodebuild` errors in seconds instead of me
pasting them back to Windows. Same repo, same tool, two machines.

Practical notes:

- Pick a provider with **Xcode pre-installed**. It's a ~20GB download plus a long
first-launch component install — don't burn rented hours on it.
- Don't spin up and destroy daily. Setup cost (Xcode, certs, Homebrew, Node,
Claude Code, repo) is real. Keep one machine for the duration of active work.

### Testable on Windows without a Mac

Structure the code so the **TfNSW API client and GTFS-R protobuf parsing are
plain logic, decoupled from UI**. That layer can be written and tested on Windows.
Only SwiftUI and ActivityKit are genuinely blind-written.

**Revised 2026-07-27: Python, not Node.** The original "prototype in Node" reasoning
assumed Option A might share TypeScript with the app. With §5.4 resolved to Swift, the
port target is Swift either way and Node shares nothing — while Python is the stronger
language here and wins decisively on Phase 0's analysis half. Built and tested: see
`collector/`.

---

## 7. Phased plan

Do not skip ahead. Each phase de-risks the next.

**Revised 2026-07-27: Phases 0 and 1 overlap.** Phase 1 cannot start until Apple
Developer enrolment clears (24–48h+ for identity verification), and Phase 0 is an
unattended job needing a week of calendar time but about an hour of attention. Running
them serially wastes a week for no risk reduction. Start the collector, then start
Phase 1 as soon as enrolment lands.

### Phase 0 — Validate the premise (no app, no Mac, no cost)

Poll the Trip Planner API for my Chatswood commute on a schedule. Log its output
alongside what Google Maps shows for the same trip, over ~1 week. Runs on my VPS,
a laptop cron, or GitHub Actions.

**Built.** See `collector/` — Python, `uv run nextstop`, 48 tests passing offline.
Blocked only on a TfNSW API key and a Google Routes key.

**Goal:** hard evidence that the accuracy gap is real and worth building for.
Produces a comparison dataset that makes a good README if this goes open source.

**Sharpened:** comparing two APIs to each other only proves they disagree, not which is
right. Ground truth comes from two iOS Shortcuts ("Boarded"/"Arrived") that POST a
timestamp to the collector. Without those the report says so rather than overclaiming.

### Phase 1 — Live Activity spike (the make-or-break test)

Build the smallest possible app whose only job is: start a Live Activity, get
backgrounded, and keep updating 10+ minutes later while I walk around Chatswood
with the phone locked in my pocket.

**Goal:** answer whether R3/R4 are achievable on the chosen stack, and settle
the Option A vs Option B decision in §5.4. **If this fails, stop and rethink
before writing any real features.**

### Phase 2 — Core journey flow

Trip Planner integration, route display, departure times. R1.

### Phase 3 — Map

Route line, live vehicle position, current location. R2.

### Phase 4 — Alerts and disruptions

Service Alerts, replacement services, trackwork, hop-off geofencing. R4, R5.

### Phase 5 — Polish, then decide on open-sourcing

---

## 8. Open questions and known risks

Flag these when relevant; don't paper over them.

1. ~~**Background JS suspension (Option A).**~~ **Closed 2026-07-27.** Expo documents
 push as the only background update path, which is what settled §5.4. No longer an
 open question — it is a decided constraint.
2. **Geofence reliability — UPGRADED, now the largest open risk.** GPS is unavailable
 for most of the Chatswood corridor, so region monitoring cannot be the primary
 mechanism for R4. §5.2 has been redesigned around a pre-scheduled local notification
 with geofencing as precision on top. The remaining unknown is how far the Trip
 Planner ETA drifts over a tunnel segment with no correction — that determines how
 early the notification has to fire, and it is measurable in Phase 0 data.
3. **Battery.** Background location for a whole commute, every day. Needs
 measuring, not assuming.
4. **Blind-written SwiftUI.** Expect the first Mac session to be mostly
 compile-error triage regardless of which stack we choose. Budget for it.
5. ~~**Signing and provisioning from Windows.**~~ **Largely closed 2026-07-27.** The
 App Manager concern is about team roles; on an **Individual** membership you are the
 Account Holder and hold every permission, so it does not apply. Enrol as Individual.
 The developer portal is a website and works fine from Windows, and `xcodebuild
 -allowProvisioningUpdates` with an App Store Connect API key handles entitlements
 without any GUI. App Groups are still required to share data between app and widget
 extension.
6. **Trip Planner response shape is assumed, not observed.** The collector's parsers
 were written from the published v3.3 manual with no API key available. They are
 deliberately tolerant of missing fields, but the first real response should be
 captured (`nextstop collect-once --raw`) and turned into a fixture. Metro's product
 class is believed to be `2`, which the manual does not list — confirm it.

---

## 9. Explicitly decided against

- Reimplementing routing from static GTFS — use the Trip Planner API.
- **Expo / React Native (added 2026-07-27)** — cannot update a Live Activity locally
while backgrounded; its only documented background path is APNs push, which §5.1
and §9 already reject. See §5.4.
- **A Phase 1 stack bake-off (added 2026-07-27)** — the decision followed from §5.1
rather than needing evidence, so building the spike twice would have cost a week to
confirm what the architecture already forced.
- Xcode Cloud — requires Xcode to configure.
- Buying a Mac — not at this stage. Revisit if the project survives Phase 1.
- Shipping to the App Store — TestFlight is sufficient.
- High-frequency APNs Live Activity updates — budget throttling makes it
unreliable.

---

## 10. How I want you to work

- Tell me what you're doing and why before doing it. I'm verifying, not
rubber-stamping.
- When something in this brief turns out to be wrong, **update this file**.
It should stay the source of truth.
- Prefer boring, debuggable solutions. I can't attach a debugger from Windows.
- Log verbosely. When something fails on device I need to be able to tell you
what happened without a Mac in front of me.

---

## 11. Immediate next actions

Blocking, in order. The first two are mine, not Claude's.

1. **Register a TfNSW Open Data API key.** Free, near-instant, at
opendata.transport.nsw.gov.au → Applications → Create Application. Subscribe it to
**Trip Planner** at minimum. Blocks all of Phase 0.
2. **Enrol in the Apple Developer Program as an Individual** (~USD $99/yr).
Verification can take 24–48h+ and it gates Phase 1 entirely, so start it first even
though Phase 0 comes first.
3. **Google Cloud project** with billing enabled and the Routes API turned on. Free
tier covers Phase 0 volume. Needed only for the comparison arm.
4. Then: `nextstop resolve-stops`, check the chosen IDs, `nextstop collect-once --raw`,
capture the first real response as a fixture, and start `nextstop schedule`.

