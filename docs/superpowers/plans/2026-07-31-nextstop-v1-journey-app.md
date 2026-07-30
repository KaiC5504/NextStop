# NextStop v1 — Journey App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the NextStop iOS spike into an app that plans a journey to anywhere in NSW, shows live departure times with an honest indication of whether they are real, draws the route properly on a map, and lets the user mark each prediction right or wrong.

**Architecture:** A native SwiftUI app talking directly to the TfNSW Trip Planner v1 API — `stop_finder` for destination search, `trip` for routing. No backend. The API key is entered once in Settings and stored in the iOS Keychain. MapKit renders per-leg polylines from the `coords` array TfNSW already returns. Recents, saved places, and prediction feedback are stored as a JSON file in the app's Documents directory.

**Tech Stack:** Swift 5 language mode, SwiftUI, MapKit, Foundation `URLSession`, XCTest. XcodeGen generates the project. Python 3.13 + Typer + SQLAlchemy for the one collector task.

## Status — Tasks 1–6 complete (merged to `main` as `068fb11`)

49 iOS tests and 122 Python tests pass; both CI screenshots verified. Five pushes, as budgeted, though not the five the plan drew: Tasks 3–5 went in one push because they are disjoint logic layers, and two of the five were spent on defects found in CI.

Seven places where reality contradicted the plan:

| What the plan said | What was true |
| --- | --- |
| Route label = `transportation.number` | That is the long form — the Metro sends `"M1 Metro North West & Bankstown Line"`. `disassembledName` (`"M1"`) is the one that fits a badge. |
| Light Rail `#DD1E25` "confirmed" | That is the L2 *line* colour. The mode colour is `#EE343F`, stated by TfNSW staff on Open Data forum thread 1040 — which also confirmed Bus, Ferry and Coach as written. |
| Fallback origin `"10101100"` | `stop_finder` gives Chatswood Station as `206710`. |
| `-initialScreen home` screenshots Home | A fresh simulator has no key, so the first-run sheet covered it. Passing the argument at all now suppresses that sheet. |
| Early departure at −150 s is `.early(2)` | −150 s is exactly 2.5 minutes, so the expectation pinned a rounding tiebreak rather than the behaviour. Tested at −185 s instead, mirroring the late case. |
| `tfnswOriginString` on a `@MainActor` class | It reads no state; main-actor isolation only stopped a nonisolated test from calling a pure formatter. Now `nonisolated`. |
| `MapCameraPosition.automatic` | Frames the whole globe with no journey and no fix — the exact state the app launches in. Now `.userLocation(fallback:)` over Sydney. |

Task 7 is the user's: install from TestFlight, paste the key, ride something.

## Global Constraints

- **Deployment target iOS 26.0**, `SWIFT_VERSION = 5.0`. Both are set in `ios/project.yml` and must not change.
- **There is no Mac and no local Swift toolchain.** Every Swift test and build runs on GitHub Actions (`macos-latest`). The edit→result loop is roughly 5 minutes.
- **This plan has exactly five pushes** (Tasks 2–6). A Swift compile reports errors from every file in one log, so a larger batch costs the same round trip and returns more information. Do not push mid-task to "check progress" — it buys nothing and costs five minutes.
- **There are no "write the test, push, watch it fail" steps.** Red-first earns its place when a test could pass vacuously. Here every such failure would be `cannot find 'X' in scope`, which proves nothing about the test. Write the test and the implementation together.
- **Python tests do run locally on Windows** via `uv run pytest` from `collector/`. Task 1 is the only task with a fast loop.
- **The TfNSW API key must never enter the repo, CI, or the app binary.** Keychain only, entered by the user at runtime. Hard floor, no exceptions.
- **Google Maps Platform APIs are forbidden as a data source.** MapKit only.
- **The repo is private** because `PROJECT_BRIEF.md`, `collector/README.md`, and `collector/src/nextstop_collector/watchlist.py` contain a home address.
- **Do not break the Live Activity spike.** `SpikeControlView`, `ActivityHarnessView`, `DebugLogView`, `SpikeSession`, `LiveActivityController`, `ExecutionHolder`, and everything under `Sources/Widget` are working code verified on a real iPhone. They move behind a developer menu. `SpikeControlView.swift:5` uses `@Environment(SpikeSession.self)`, which traps when absent — anything presenting those screens must re-inject the session.
- **Design language:** dark theme, glass surfaces, real motion. Colours and sizes come from `Theme.swift`, never hardcoded at call sites.
- **Comment style:** comment the *why*, never the *what*. Match the sparse, high-value density of the existing files.

---

## File Structure

**New Swift source, under `ios/Sources/App/`:**

| Path | Responsibility |
| --- | --- |
| `Theme.swift` | Colour, spacing, radius tokens and a hex `Color` initialiser. |
| `TfNSW/TransitMode.swift` | Product class → mode, display name, symbol, official colour. |
| `TfNSW/TripDTO.swift` | `Decodable` mirrors of the raw `trip` JSON. |
| `TfNSW/StopFinderDTO.swift` | `Decodable` mirrors of the raw `stop_finder` JSON. |
| `TfNSW/Journey.swift` | Domain model (`Journey`, `Leg`, `LegStop`) and DTO mapping. |
| `TfNSW/TfNSWClient.swift` | URL building, auth header, `URLSession` calls, typed errors. |
| `Storage/KeychainStore.swift` | The API key. |
| `Storage/Feedback.swift` | `PredictionFeedback`. |
| `Storage/LocalStore.swift` | Recents, saved places, feedback. One JSON file. |
| `Map/JourneyMapView.swift` | `MapFraming` plus the map itself. |
| `LocationProvider.swift` | Current location and the EFA coordinate format. |
| `AppModel.swift` | Observable app state. |
| `UI/DepartureStatus.swift` | On time / late / early / scheduled-only. |
| `UI/GlassCard.swift` | Glass surface modifier and bottom card. |
| `UI/LegRow.swift` | One leg, including the feedback control. |
| `UI/HomeView.swift`, `UI/SearchSheet.swift`, `UI/JourneyOptionsView.swift`, `UI/LiveJourneyView.swift`, `UI/SettingsView.swift` | The five screens. |

**Modified:** `ios/project.yml`, `ios/Sources/App/NextStopApp.swift:21-40`, `.github/workflows/ios-compile.yml`, `collector/src/nextstop_collector/cli.py`.

**New tests, under `ios/Tests/`:** `FixtureLoader.swift`, `FixtureLoaderTests.swift`, `TransitModeTests.swift`, `TripDecodingTests.swift`, `JourneyMappingTests.swift`, `KeychainStoreTests.swift`, `TfNSWClientTests.swift`, `LocalStoreTests.swift`, `MapRegionTests.swift`, `AppModelTests.swift`, `DepartureStatusTests.swift`, `LocationProviderTests.swift`, plus `Fixtures/trip-sample.json` and `Fixtures/stopfinder-sample.json`.

---

### Task 1: `nextstop observe` CLI command

Backfills board/arrive times noted by hand into the collector database. The app supersedes this **once it ships**, which is several pushes away — every commute between now and then is data that otherwise goes unrecorded. Local test loop, no CI.

**Files:**
- Modify: `collector/src/nextstop_collector/cli.py` (after `shortcut_command`, around line 307)
- Test: `collector/tests/test_observe_cli.py` (create)

**Interfaces:**
- Consumes: `Observation`, `session_scope`, `now_utc`, `to_sydney`, `BY_KEY` (already imported in `cli.py`).
- Produces: CLI command `nextstop observe`. Nothing downstream depends on it.

- [ ] **Step 1: Write the test**

Create `collector/tests/test_observe_cli.py`:

```python
from typer.testing import CliRunner

from nextstop_collector.cli import app
from nextstop_collector.storage.db import session_scope
from nextstop_collector.storage.models import Observation

runner = CliRunner()


def _observations(corridor: str) -> list[Observation]:
    with session_scope() as session:
        rows = session.query(Observation).filter(Observation.corridor == corridor).all()
        # Detach before the session closes so assertions can still read attributes.
        for row in rows:
            session.expunge(row)
        return rows


class TestObserveCommand:
    def test_records_an_observation_now(self):
        result = runner.invoke(app, ["observe", "boarded", "--corridor", "cli-now"])
        assert result.exit_code == 0, result.output
        rows = _observations("cli-now")
        assert len(rows) == 1
        assert rows[0].event == "boarded"

    def test_accepts_a_sydney_local_time(self):
        result = runner.invoke(
            app,
            ["observe", "arrived", "--corridor", "cli-at", "--at", "2026-07-28 09:03"],
        )
        assert result.exit_code == 0, result.output
        rows = _observations("cli-at")
        assert len(rows) == 1
        # 09:03 Sydney in July is UTC+10, so 23:03 the previous day in UTC.
        assert rows[0].recorded_at.hour == 23
        assert rows[0].recorded_at.day == 27

    def test_rejects_an_unknown_event(self):
        result = runner.invoke(app, ["observe", "teleported", "--corridor", "cli-bad"])
        assert result.exit_code != 0

    def test_rejects_an_unparseable_time(self):
        result = runner.invoke(
            app, ["observe", "boarded", "--corridor", "cli-bad2", "--at", "yesterday-ish"]
        )
        assert result.exit_code != 0
```

- [ ] **Step 2: Implement the command**

Add these imports to the top of `cli.py` if absent:

```python
from datetime import datetime
from zoneinfo import ZoneInfo

from .storage.db import session_scope
from .storage.models import Observation
from .timeutil import now_utc, to_sydney
```

Then, after `shortcut_command`:

```python
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
```

- [ ] **Step 3: Run the tests**

```bash
cd collector && uv run pytest tests/test_observe_cli.py -v && uv run pytest -q
```

Expected: 4 passed in the first run, no failures in the second.

- [ ] **Step 4: Commit**

```bash
git add collector/src/nextstop_collector/cli.py collector/tests/test_observe_cli.py
git commit -m "Add nextstop observe for recording ground truth by hand"
```

---

### Task 2 — PUSH 1: Test target, fixtures, and CI that runs tests

Without this there is no way to test any Swift from Windows. Everything after depends on it.

**Files:**
- Create: `ios/Tests/Fixtures/trip-sample.json`, `ios/Tests/Fixtures/stopfinder-sample.json`
- Create: `ios/Tests/FixtureLoader.swift`, `ios/Tests/FixtureLoaderTests.swift`
- Modify: `ios/project.yml` (test target, scheme, corrected plist comment and location strings)
- Modify: `.github/workflows/ios-compile.yml`

**Interfaces:**
- Produces: `Fixture.data(_ name: String) -> Data`.

- [ ] **Step 1: Capture the fixtures from the live API**

Uses the key already in `collector/.env` and never prints it. The departure time is pinned to a weekday morning so the response contains Metro, bus, and walk legs rather than the NightRide-only result a 2am call returns.

```bash
cd collector && uv run python -c "
import json, pathlib
from datetime import datetime
from zoneinfo import ZoneInfo
from nextstop_collector.storage.db import init_db
from nextstop_collector.tfnsw.client import TfnswClient
from nextstop_collector.tfnsw.stops import find_candidates

init_db()
out = pathlib.Path('../ios/Tests/Fixtures'); out.mkdir(parents=True, exist_ok=True)
when = datetime(2026, 8, 3, 8, 0, tzinfo=ZoneInfo('Australia/Sydney'))
with TfnswClient() as c:
    sf = c.stop_finder('Chatswood', max_results=10)
    (out / 'stopfinder-sample.json').write_text(json.dumps(sf, indent=2), encoding='utf-8')
    o = find_candidates(c, 'Chatswood Station', limit=1)[0]
    d = find_candidates(c, 'University of Sydney, City Rd', limit=1)[0]
    trip = c.trip(o['id'], d['id'], when)
# Two journeys is plenty to test against and keeps the fixture reviewable.
trip['journeys'] = (trip.get('journeys') or [])[:2]
(out / 'trip-sample.json').write_text(json.dumps(trip, indent=2), encoding='utf-8')
print('legs per journey:', [len(j.get('legs') or []) for j in trip['journeys']])
print('classes:', [[(l.get('transportation') or {}).get('product', {}).get('class') for l in j['legs']] for j in trip['journeys']])
"
```

Expected: at least one journey with a class 99 or 100 (walk) leg and a class 2 or 5 leg. If the date has passed, bump it to the next Monday.

- [ ] **Step 2: Add the test target and scheme to `ios/project.yml`**

Append at the end of the file. `NextStopTests` must sit at the same indent as `NextStopWidget`; `schemes:` at the same indent as `targets:`.

```yaml
  NextStopTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: NextStop
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        # An unhosted XCTest bundle has no keychain access group, and every Keychain
        # test then fails with errSecMissingEntitlement (-34018). Hosting it in the app
        # is the fix, and it is cheaper to set now than to diagnose over a 5-minute loop.
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/NextStop.app/NextStop"
        BUNDLE_LOADER: "$(TEST_HOST)"

# Declared explicitly rather than left to XcodeGen's defaults: `xcodebuild test` only runs
# a test target attached to the scheme's test action, and declaring any scheme replaces
# the one XcodeGen would have generated — so the build targets must be listed too.
schemes:
  NextStop:
    build:
      targets:
        NextStop: all
        NextStopTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - NextStopTests
```

- [ ] **Step 3: Correct two now-stale entries in `ios/project.yml`**

At `ios/project.yml:56-58`, the comment explaining `ITSAppUsesNonExemptEncryption` says the app makes no network calls. That stops being true in Task 4, and a future reader would take it as a reason to change the flag. Replace the comment with:

```yaml
        # The value stays false: the app makes only standard HTTPS calls to Transport NSW,
        # and platform TLS is exempt from the export-encryption question. Without this key
        # every upload sits in TestFlight as "Missing Compliance", which blocks install.
```

At `ios/project.yml:79-84`, both location strings describe only the Live Activity use. Location also chooses the journey origin from Task 5. Replace both values with:

```yaml
        NSLocationWhenInUseUsageDescription: >-
          NextStop uses your location to plan journeys from where you are and to keep the
          arrival countdown updating while your phone is locked. Nothing is uploaded or
          stored off the device.
        NSLocationAlwaysAndWhenInUseUsageDescription: >-
          NextStop uses your location to plan journeys from where you are and to keep the
          arrival countdown updating while your phone is locked. Nothing is uploaded or
          stored off the device.
```

Leave `UIBackgroundModes: location` alone. `ExecutionHolder.swift:99` sets `allowsBackgroundLocationUpdates = true`, and that spike is being preserved.

- [ ] **Step 4: Write the fixture loader and its smoke test**

Create `ios/Tests/FixtureLoader.swift`:

```swift
import Foundation

enum Fixture {
    /// A resource missing from the test bundle is a project-generation fault, not a test
    /// failure worth recovering from — fail loudly with the name that was not found.
    static func data(_ name: String) -> Data {
        guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json") else {
            fatalError("fixture \(name).json is not in the test bundle")
        }
        return try! Data(contentsOf: url)
    }
}

private final class BundleToken {}
```

Create `ios/Tests/FixtureLoaderTests.swift`:

```swift
import XCTest

final class FixtureLoaderTests: XCTestCase {
    /// One smoke test, not one per fixture. Later suites decode both files for real; this
    /// exists only to turn "resource not copied into the bundle" into a clear failure.
    func testFixturesAreBundled() throws {
        let trip = try JSONSerialization.jsonObject(with: Fixture.data("trip-sample")) as? [String: Any]
        XCTAssertFalse((trip?["journeys"] as? [[String: Any]] ?? []).isEmpty)

        let stops = try JSONSerialization.jsonObject(with: Fixture.data("stopfinder-sample")) as? [String: Any]
        XCTAssertFalse((stops?["locations"] as? [[String: Any]] ?? []).isEmpty)
    }
}
```

- [ ] **Step 5: Add the test step to CI**

In `.github/workflows/ios-compile.yml`, insert immediately after `Build for simulator`:

```yaml
      - name: Run unit tests
        run: |
          set -o pipefail
          xcodebuild test \
            -project ios/NextStop.xcodeproj \
            -scheme NextStop \
            -destination "id=${{ steps.sim.outputs.udid }}" \
            -configuration Debug \
            -derivedDataPath build \
            CODE_SIGN_IDENTITY="-" \
            CODE_SIGNING_REQUIRED=NO \
            CODE_SIGNING_ALLOWED=YES
```

- [ ] **Step 6: Commit and push**

```bash
git add ios/project.yml ios/Tests .github/workflows/ios-compile.yml
git commit -m "Add an iOS unit test target with captured TfNSW fixtures"
git push
```

Expected: the workflow reaches "Run unit tests" and `FixtureLoaderTests` passes. A failure at `xcodegen generate` means the appended YAML is indented wrong.

---

### Task 3 — PUSH 2: Theme, modes, decoding, and the domain model

**Files:**
- Create: `ios/Sources/App/Theme.swift`, `ios/Sources/App/TfNSW/TransitMode.swift`, `ios/Sources/App/TfNSW/TripDTO.swift`, `ios/Sources/App/TfNSW/StopFinderDTO.swift`, `ios/Sources/App/TfNSW/Journey.swift`
- Test: `ios/Tests/TransitModeTests.swift`, `ios/Tests/TripDecodingTests.swift`, `ios/Tests/JourneyMappingTests.swift`

**Interfaces:**
- Produces:
  - `enum Theme` — `Theme.Colors.{background,surface,stroke,textPrimary,textSecondary,onTime,late,veryLate,noRealtime}`, `Theme.Spacing.{xs,s,m,l,xl}`, `Theme.Radius.{card,pill}`; `Color.init(hex: UInt32)`
  - `enum TransitMode: Equatable` — `init(productClass: Int?)`, `displayName`, `symbolName`, `tint`, `isWalking`
  - `TripDTO`, `JourneyDTO`, `LegDTO`, `PlaceDTO`, `TransportationDTO`, `ProductDTO`, `NamedDTO`, `StopFinderDTO`, `LocationDTO`, `JSONDecoder.tfnswDecoder`
  - `struct Leg: Identifiable` with **`let id: String`** — `mode`, `route: String?`, `headsign: String?`, `originName`, `destinationName`, `plannedDeparture/estimatedDeparture/plannedArrival/estimatedArrival: Date?`, `hasRealtime: Bool`, `path: [CLLocationCoordinate2D]`, `stops: [LegStop]`, `durationSeconds: Int?`, computed `departure`, `arrival`, `delaySeconds`
  - `struct Journey: Identifiable` with **`let id: String`** — `legs`, `departure`, `arrival`, `duration`, `transitLegs`, `static func list(from: TripDTO) -> [Journey]`
  - `struct LegStop: Identifiable`

- [ ] **Step 1: Write `Theme.swift`**

```swift
import SwiftUI

enum Theme {
    enum Colors {
        static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
        static let surface = Color.white.opacity(0.08)
        static let stroke = Color.white.opacity(0.12)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)

        static let onTime = Color(hex: 0x55A868)
        static let late = Color(hex: 0xDD8452)
        static let veryLate = Color(hex: 0xC44E52)
        // Deliberately grey rather than a warning colour. Absent realtime is not a problem
        // with the service, it is a limit on what the app can honestly claim.
        static let noRealtime = Color.white.opacity(0.45)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }

    enum Radius {
        static let card: CGFloat = 28
        static let pill: CGFloat = 12
    }
}

extension Color {
    /// Mode colours are published as hex by TfNSW. Storing them as hex rather than decimal
    /// components keeps them checkable against the brand guidance by eye.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
```

- [ ] **Step 2: Write `TfNSW/TransitMode.swift`**

Train, Metro and Light Rail are confirmed against the published specifications (RGB 246/137/31 PMS 151C; RGB 22/131/136 PMS 321; the L2 line colour CMYK 5/100/100/2). Bus, Ferry and Coach are the widely-published values and are **not** confirmed from a primary source — Step 8 handles that.

```swift
import SwiftUI

/// TfNSW product classes, per the Trip Planner v3.3 manual and confirmed against live
/// responses. Colours are the published TfNSW mode colours — using anything else costs the
/// instant recognition that makes a transit map readable at a glance.
enum TransitMode: Equatable {
    case train, metro, lightRail, bus, coach, ferry, schoolBus, walk, cycle, unknown

    init(productClass: Int?) {
        switch productClass {
        case 1: self = .train
        case 2: self = .metro
        case 4: self = .lightRail
        case 5: self = .bus
        case 7: self = .coach
        case 9: self = .ferry
        case 11: self = .schoolBus
        // TfNSW uses both 99 and 100 for walking in the same response.
        case 99, 100: self = .walk
        case 107: self = .cycle
        default: self = .unknown
        }
    }

    var isWalking: Bool { self == .walk || self == .cycle }

    var displayName: String {
        switch self {
        case .train: "Train"
        case .metro: "Metro"
        case .lightRail: "Light Rail"
        case .bus: "Bus"
        case .coach: "Coach"
        case .ferry: "Ferry"
        case .schoolBus: "School Bus"
        case .walk: "Walk"
        case .cycle: "Cycle"
        case .unknown: "Service"
        }
    }

    var symbolName: String {
        switch self {
        case .train: "tram.fill"
        case .metro: "train.side.front.car"
        case .lightRail: "cablecar.fill"
        case .bus: "bus.fill"
        case .coach: "bus.doubledecker.fill"
        case .ferry: "ferry.fill"
        case .schoolBus: "bus"
        case .walk: "figure.walk"
        case .cycle: "bicycle"
        case .unknown: "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .train: Color(hex: 0xF6891F)
        case .metro: Color(hex: 0x168388)
        case .lightRail: Color(hex: 0xDD1E25)
        case .bus, .schoolBus: Color(hex: 0x00B5EF)
        case .coach: Color(hex: 0x732A82)
        case .ferry: Color(hex: 0x5AB031)
        case .walk, .cycle: Theme.Colors.noRealtime
        case .unknown: Theme.Colors.textSecondary
        }
    }
}
```

- [ ] **Step 3: Write `ios/Tests/TransitModeTests.swift`**

```swift
import XCTest
@testable import NextStop

final class TransitModeTests: XCTestCase {
    func testKnownProductClassesMap() {
        XCTAssertEqual(TransitMode(productClass: 1), .train)
        XCTAssertEqual(TransitMode(productClass: 2), .metro)
        XCTAssertEqual(TransitMode(productClass: 4), .lightRail)
        XCTAssertEqual(TransitMode(productClass: 5), .bus)
        XCTAssertEqual(TransitMode(productClass: 7), .coach)
        XCTAssertEqual(TransitMode(productClass: 9), .ferry)
        XCTAssertEqual(TransitMode(productClass: 11), .schoolBus)
    }

    /// TfNSW uses both 99 and 100 for walking legs in the same response. Missing this
    /// renders a walk as a bus, in bus blue, on the map.
    func testBothWalkClassesMap() {
        XCTAssertEqual(TransitMode(productClass: 99), .walk)
        XCTAssertEqual(TransitMode(productClass: 100), .walk)
        XCTAssertTrue(TransitMode(productClass: 100).isWalking)
    }

    func testMissingOrUnexpectedClassIsUnknown() {
        XCTAssertEqual(TransitMode(productClass: nil), .unknown)
        XCTAssertEqual(TransitMode(productClass: 42), .unknown)
        XCTAssertFalse(TransitMode(productClass: nil).isWalking)
    }
}
```

- [ ] **Step 4: Write `TfNSW/TripDTO.swift`**

```swift
import Foundation

struct TripDTO: Decodable {
    let journeys: [JourneyDTO]?
}

struct JourneyDTO: Decodable {
    let legs: [LegDTO]?
}

struct LegDTO: Decodable {
    let duration: Int?
    let coords: [[Double]]?
    let origin: PlaceDTO?
    let destination: PlaceDTO?
    let transportation: TransportationDTO?
    let isRealtimeControlled: Bool?
    let stopSequence: [PlaceDTO]?
}

struct PlaceDTO: Decodable {
    let id: String?
    let name: String?
    let disassembledName: String?
    let coord: [Double]?
    let departureTimePlanned: Date?
    let departureTimeEstimated: Date?
    let arrivalTimePlanned: Date?
    let arrivalTimeEstimated: Date?
}

struct TransportationDTO: Decodable {
    let number: String?
    let disassembledName: String?
    let product: ProductDTO?
    let destination: NamedDTO?
}

struct ProductDTO: Decodable {
    let productClass: Int?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case productClass = "class"
        case name
    }
}

struct NamedDTO: Decodable {
    let name: String?
}

extension JSONDecoder {
    /// Every field on these DTOs is optional on purpose. The Trip Planner omits keys rather
    /// than sending nulls, and it omits different ones depending on mode, time of day, and
    /// whether a service is realtime-tracked. One missing key must never cost the whole
    /// journey.
    static var tfnswDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 5: Write `TfNSW/StopFinderDTO.swift`**

```swift
import Foundation

struct StopFinderDTO: Decodable {
    let locations: [LocationDTO]?
}

struct LocationDTO: Decodable {
    let id: String?
    let name: String?
    let disassembledName: String?
    let isBest: Bool?
    let matchQuality: Int?
}
```

- [ ] **Step 6: Write `ios/Tests/TripDecodingTests.swift`**

```swift
import XCTest
@testable import NextStop

final class TripDecodingTests: XCTestCase {
    private func decoded() throws -> TripDTO {
        try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
    }

    func testJourneysAndLegsDecode() throws {
        let journeys = try XCTUnwrap(decoded().journeys)
        XCTAssertFalse(journeys.isEmpty)
        XCTAssertFalse(try XCTUnwrap(journeys[0].legs).isEmpty)
    }

    /// `coords` is what makes a real map possible. A leg drawn as a straight line between
    /// two stops is the failure this test exists to catch.
    func testTransitLegsCarryRouteGeometry() throws {
        let legs = try XCTUnwrap(decoded().journeys?.first?.legs)
        let transit = legs.filter { !TransitMode(productClass: $0.transportation?.product?.productClass).isWalking }
        XCTAssertFalse(transit.isEmpty, "fixture has no transit leg")
        for leg in transit {
            XCTAssertGreaterThan(leg.coords?.count ?? 0, 2)
            let first = try XCTUnwrap(leg.coords?.first)
            XCTAssertEqual(first.count, 2)
            XCTAssertTrue((-45...(-25)).contains(first[0]), "latitude \(first[0]) is not in NSW")
            XCTAssertTrue((140...155).contains(first[1]), "longitude \(first[1]) is not in NSW")
        }
    }

    func testTimesDecodeAsDates() throws {
        let leg = try XCTUnwrap(decoded().journeys?.first?.legs?.first)
        XCTAssertNotNil(leg.origin?.departureTimePlanned)
        XCTAssertNotNil(leg.destination?.arrivalTimePlanned)
    }

    func testProductClassDecodesFromReservedKeyword() throws {
        let legs = try XCTUnwrap(decoded().journeys?.first?.legs)
        XCTAssertTrue(legs.contains { $0.transportation?.product?.productClass != nil })
    }

    func testStopSequenceCarriesNamedCoordinates() throws {
        let legs = try XCTUnwrap(decoded().journeys?.first?.legs)
        let withStops = try XCTUnwrap(legs.first { ($0.stopSequence?.count ?? 0) > 1 })
        let stop = try XCTUnwrap(withStops.stopSequence?.first)
        XCTAssertEqual(stop.coord?.count, 2)
        XCTAssertNotNil(stop.name ?? stop.disassembledName)
    }
}
```

If `testTimesDecodeAsDates` fails, the API returned fractional seconds — swap `.iso8601` for a `DateFormatter` with format `yyyy-MM-dd'T'HH:mm:ssZ` and locale `en_US_POSIX`.

- [ ] **Step 7: Write `TfNSW/Journey.swift`**

Both `id`s are **derived from planned times, never from `UUID()` or an array index.** The journey screen re-plans every 30 seconds; a fresh identity each time makes SwiftUI tear down and rebuild every row, and makes "which legs has the user already rated?" unanswerable. Planned times do not move between refreshes. Estimated times do, which is exactly why they are not part of the key.

```swift
import CoreLocation
import Foundation

struct LegStop: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let departure: Date?
}

struct Leg: Identifiable {
    let id: String
    let mode: TransitMode
    let route: String?
    let headsign: String?
    let originName: String
    let destinationName: String
    let plannedDeparture: Date?
    let estimatedDeparture: Date?
    let plannedArrival: Date?
    let estimatedArrival: Date?
    let hasRealtime: Bool
    let path: [CLLocationCoordinate2D]
    let stops: [LegStop]
    let durationSeconds: Int?

    var departure: Date? { estimatedDeparture ?? plannedDeparture }
    var arrival: Date? { estimatedArrival ?? plannedArrival }

    /// Nil when there is no estimate to compare, which is different from zero. Zero means
    /// "tracked and on time"; nil means "nobody is tracking this".
    var delaySeconds: Int? {
        guard let planned = plannedDeparture, let estimated = estimatedDeparture else { return nil }
        return Int(estimated.timeIntervalSince(planned))
    }
}

struct Journey: Identifiable {
    let id: String
    let legs: [Leg]

    var departure: Date? { legs.first?.departure }
    var arrival: Date? { legs.last?.arrival }
    var transitLegs: [Leg] { legs.filter { !$0.mode.isWalking } }

    var duration: TimeInterval? {
        guard let departure, let arrival else { return nil }
        return arrival.timeIntervalSince(departure)
    }

    static func list(from dto: TripDTO) -> [Journey] {
        (dto.journeys ?? []).compactMap { journey in
            let legs = (journey.legs ?? []).map(Leg.init(dto:))
            guard !legs.isEmpty else { return nil }
            return Journey(id: legs.map(\.id).joined(separator: "|"), legs: legs)
        }
    }
}

private extension CLLocationCoordinate2D {
    /// TfNSW sends `[latitude, longitude]`, the opposite order to GeoJSON. Getting this
    /// backwards puts the whole route in the Indian Ocean.
    init?(pair: [Double]) {
        guard pair.count == 2 else { return nil }
        self.init(latitude: pair[0], longitude: pair[1])
    }
}

extension Leg {
    init(dto: LegDTO) {
        let transportation = dto.transportation
        let mode = TransitMode(productClass: transportation?.product?.productClass)
        let route = transportation?.number ?? transportation?.disassembledName
        let originName = dto.origin?.disassembledName ?? dto.origin?.name ?? ""
        let planned = dto.origin?.departureTimePlanned
        let plannedKey = planned.map { String(Int($0.timeIntervalSince1970)) } ?? "?"

        self.init(
            id: "\(mode)|\(route ?? "")|\(originName)|\(plannedKey)",
            mode: mode,
            route: route,
            headsign: transportation?.destination?.name,
            originName: originName,
            destinationName: dto.destination?.disassembledName ?? dto.destination?.name ?? "",
            plannedDeparture: planned,
            estimatedDeparture: dto.origin?.departureTimeEstimated,
            plannedArrival: dto.destination?.arrivalTimePlanned,
            estimatedArrival: dto.destination?.arrivalTimeEstimated,
            hasRealtime: dto.isRealtimeControlled ?? false,
            path: (dto.coords ?? []).compactMap(CLLocationCoordinate2D.init(pair:)),
            stops: (dto.stopSequence ?? []).compactMap(LegStop.init(dto:)),
            durationSeconds: dto.duration
        )
    }
}

extension LegStop {
    init?(dto: PlaceDTO) {
        guard let coordinate = dto.coord.flatMap(CLLocationCoordinate2D.init(pair:)) else { return nil }
        self.init(
            id: dto.id ?? UUID().uuidString,
            name: dto.disassembledName ?? dto.name ?? "",
            coordinate: coordinate,
            departure: dto.departureTimeEstimated ?? dto.departureTimePlanned
        )
    }
}
```

- [ ] **Step 8: Write `ios/Tests/JourneyMappingTests.swift`**

```swift
import CoreLocation
import XCTest
@testable import NextStop

final class JourneyMappingTests: XCTestCase {
    private func journeys() throws -> [Journey] {
        let dto = try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
        return Journey.list(from: dto)
    }

    private func leg(planned: Date?, estimated: Date?, realtime: Bool) -> Leg {
        Leg(
            id: "test", mode: .bus, route: "412", headsign: "USyd",
            originName: "A", destinationName: "B",
            plannedDeparture: planned, estimatedDeparture: estimated,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: realtime, path: [], stops: [], durationSeconds: 600
        )
    }

    func testJourneysAreBuiltWithLegs() throws {
        let all = try journeys()
        XCTAssertFalse(all.isEmpty)
        XCTAssertFalse(all[0].legs.isEmpty)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "journey ids must be unique")
    }

    /// Decoding the same payload twice must produce the same ids. The live screen re-plans
    /// every 30s; unstable ids make SwiftUI rebuild every row and lose which legs the user
    /// has already rated.
    func testIdsAreStableAcrossDecodes() throws {
        XCTAssertEqual(try journeys().map(\.id), try journeys().map(\.id))
        XCTAssertEqual(try journeys()[0].legs.map(\.id), try journeys()[0].legs.map(\.id))
    }

    func testPathIsConvertedToCoordinates() throws {
        let transit = try XCTUnwrap(journeys().first?.transitLegs.first)
        XCTAssertGreaterThan(transit.path.count, 2)
        XCTAssertTrue((-45...(-25)).contains(transit.path[0].latitude))
    }

    func testDepartureFallsBackToPlannedWhenNoEstimate() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let subject = leg(planned: planned, estimated: nil, realtime: false)
        XCTAssertEqual(subject.departure, planned)
        XCTAssertNil(subject.delaySeconds)
    }

    func testDelayIsTheDifferenceBetweenEstimateAndPlan() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let subject = leg(planned: planned, estimated: planned.addingTimeInterval(180), realtime: true)
        XCTAssertEqual(subject.delaySeconds, 180)
        XCTAssertEqual(subject.departure, planned.addingTimeInterval(180))
    }

    func testJourneySpansFirstDepartureToLastArrival() throws {
        let journey = try XCTUnwrap(journeys().first)
        let departure = try XCTUnwrap(journey.departure)
        let arrival = try XCTUnwrap(journey.arrival)
        XCTAssertGreaterThan(arrival, departure)
    }

    func testWalkingLegsAreExcludedFromTransitLegs() throws {
        for journey in try journeys() {
            XCTAssertFalse(journey.transitLegs.contains { $0.mode.isWalking })
        }
    }
}
```

- [ ] **Step 9: Commit and push**

```bash
git add ios/Sources/App/Theme.swift ios/Sources/App/TfNSW ios/Tests
git commit -m "Add theme tokens, mode mapping, and the journey domain model"
git push
```

Expected: `FixtureLoaderTests`, `TransitModeTests` (3), `TripDecodingTests` (5), `JourneyMappingTests` (7) all pass.

- [x] **Step 10: Confirm the three unverified mode colours** — done, and one confirmed value was wrong.

TfNSW staff stated the mode palette on the Open Data forum (thread 1040): Train `#F6891F`, Bus `#00B5EF`, Coach `#732A82`, Ferry `#5AB031`, **Light Rail `#EE343F`**. Bus, Ferry and Coach are confirmed as written. Light Rail was **not** — `#DD1E25` is the L2 *line* colour, and this app colours by mode. Corrected in `TransitMode.swift`. Metro `#168388` (PMS 321) stands.

---

### Task 4 — PUSH 3: Keychain, API client, and local storage

**Files:**
- Create: `ios/Sources/App/Storage/KeychainStore.swift`, `ios/Sources/App/Storage/Feedback.swift`, `ios/Sources/App/Storage/LocalStore.swift`, `ios/Sources/App/TfNSW/TfNSWClient.swift`
- Test: `ios/Tests/KeychainStoreTests.swift`, `ios/Tests/TfNSWClientTests.swift`, `ios/Tests/LocalStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum KeychainStore` — `save(_:) throws`, `read() -> String?`, `delete()`; `struct KeychainError: Error { let status: OSStatus }`
  - `protocol HTTPFetching { func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) }`, `extension URLSession: HTTPFetching`
  - `struct TfNSWClient` — `init(session:keyProvider:)`, `makeRequest(path:query:) throws -> URLRequest`, `journeys(originID:originType:destinationID:destinationType:departing:) async throws -> [Journey]`, `findStops(matching:) async throws -> [StopSuggestion]`
  - `enum TfNSWError: Error, Equatable { case missingKey, unauthorised, http(Int), transport }`
  - `struct StopSuggestion: Identifiable, Codable, Hashable { let id: String; let name: String; let isBest: Bool }`
  - `struct PredictionFeedback: Codable, Identifiable` + `init(leg:wasCorrect:tappedAt:)`
  - `final class LocalStore: ObservableObject` — `init(fileURL:)`, `static let shared`, `@Published private(set) recents/saved/feedback`, `addRecent(_:)`, `toggleSaved(_:)`, `isSaved(_:)`, `record(_:)`, `exportFeedbackJSON() throws -> Data`

- [ ] **Step 1: Write `Storage/KeychainStore.swift`**

```swift
import Foundation
import Security

struct KeychainError: Error {
    let status: OSStatus
}

/// The TfNSW key lives here and nowhere else — not in the repo, not in CI, not compiled
/// into the binary. The user types it once in Settings.
enum KeychainStore {
    private static let service = "com.kaichuan.nextstop"
    private static let account = "tfnsw-api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ key: String) throws {
        // Delete-then-add rather than a bare SecItemAdd, which returns errSecDuplicateItem
        // the second time the user pastes a key.
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
```

- [ ] **Step 2: Write `ios/Tests/KeychainStoreTests.swift`**

Two tests, not four. Round-tripping a value through Apple's Keychain tests Apple's code. These two cover a decision that was actually made (delete-then-add) and the first-run path the UI depends on.

```swift
import XCTest
@testable import NextStop

final class KeychainStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeychainStore.delete()
    }

    override func tearDown() {
        KeychainStore.delete()
        super.tearDown()
    }

    /// Settings opens automatically when this returns nil, so it is load-bearing.
    func testReadReturnsNilWhenNothingStored() {
        XCTAssertNil(KeychainStore.read())
    }

    func testSavingTwiceOverwrites() throws {
        try KeychainStore.save("first")
        try KeychainStore.save("second")
        XCTAssertEqual(KeychainStore.read(), "second")
    }
}
```

- [ ] **Step 3: Write `TfNSW/TfNSWClient.swift`**

`HTTPFetching` declares `fetch(_:)` rather than `data(for:)`. `URLSession`'s real method is `data(for:delegate:)`, whose full name differs from `data(for:)`, so it would not satisfy the requirement — the explicit forwarding method sidesteps the question entirely.

Origin and destination types are parameters defaulting to `"stop"`, mirroring the proven Python client at `collector/src/nextstop_collector/tfnsw/client.py:166-189`. A coordinate origin needs `"coord"` and is passed explicitly in Task 5.

```swift
import Foundation

enum TfNSWError: Error, Equatable {
    case missingKey
    case unauthorised
    case http(Int)
    case transport
}

struct StopSuggestion: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let isBest: Bool
}

protocol HTTPFetching {
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

struct TfNSWClient {
    private static let base = URL(string: "https://api.transport.nsw.gov.au/v1/tp/")!

    private let session: HTTPFetching
    private let keyProvider: () -> String?

    init(session: HTTPFetching = URLSession.shared, keyProvider: @escaping () -> String? = KeychainStore.read) {
        self.session = session
        self.keyProvider = keyProvider
    }

    func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard let key = keyProvider(), !key.isEmpty else { throw TfNSWError.missingKey }

        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "outputFormat", value: "rapidJSON"),
            URLQueryItem(name: "coordOutputFormat", value: "EPSG:4326"),
        ] + query

        var request = URLRequest(url: components.url!)
        request.setValue("apikey \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    func journeys(
        originID: String,
        originType: String = "stop",
        destinationID: String,
        destinationType: String = "stop",
        departing: Date
    ) async throws -> [Journey] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: departing)

        let request = try makeRequest(path: "trip", query: [
            URLQueryItem(name: "depArrMacro", value: "dep"),
            URLQueryItem(name: "itdDate", value: String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)),
            URLQueryItem(name: "itdTime", value: String(format: "%02d%02d", parts.hour!, parts.minute!)),
            URLQueryItem(name: "type_origin", value: originType),
            URLQueryItem(name: "name_origin", value: originID),
            URLQueryItem(name: "type_destination", value: destinationType),
            URLQueryItem(name: "name_destination", value: destinationID),
            URLQueryItem(name: "TfNSWTR", value: "true"),
        ])

        let dto: TripDTO = try await send(request)
        return Journey.list(from: dto)
    }

    func findStops(matching query: String) async throws -> [StopSuggestion] {
        let request = try makeRequest(path: "stop_finder", query: [
            URLQueryItem(name: "type_sf", value: "any"),
            URLQueryItem(name: "name_sf", value: query),
            URLQueryItem(name: "anyMaxSizeHitList", value: "12"),
        ])

        let dto: StopFinderDTO = try await send(request)
        return (dto.locations ?? [])
            .compactMap { location -> (StopSuggestion, Int)? in
                guard let id = location.id,
                      let name = location.disassembledName ?? location.name else { return nil }
                return (
                    StopSuggestion(id: id, name: name, isBest: location.isBest ?? false),
                    location.matchQuality ?? 0
                )
            }
            .sorted { left, right in
                if left.0.isBest != right.0.isBest { return left.0.isBest }
                return left.1 > right.1
            }
            .map(\.0)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.fetch(request)
        } catch {
            throw TfNSWError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw TfNSWError.transport }
        // 401 and 403 both mean the key is wrong or unsubscribed, and both need the user
        // sent to Settings rather than shown a retry button.
        if http.statusCode == 401 || http.statusCode == 403 { throw TfNSWError.unauthorised }
        guard http.statusCode == 200 else { throw TfNSWError.http(http.statusCode) }

        do {
            return try JSONDecoder.tfnswDecoder.decode(T.self, from: data)
        } catch {
            throw TfNSWError.transport
        }
    }
}
```

- [ ] **Step 4: Write `ios/Tests/TfNSWClientTests.swift`**

```swift
import XCTest
@testable import NextStop

struct StubFetcher: HTTPFetching {
    var status: Int = 200
    var payload: Data = Data()
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (payload, response)
    }
}

final class TfNSWClientTests: XCTestCase {
    func testRequestCarriesTheApiKeyAndRapidJSON() throws {
        let client = TfNSWClient(session: StubFetcher(), keyProvider: { "secret" })
        let request = try client.makeRequest(path: "trip", query: [URLQueryItem(name: "a", value: "b")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "apikey secret")
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://api.transport.nsw.gov.au/v1/tp/trip"))
        XCTAssertTrue(url.contains("outputFormat=rapidJSON"))
        XCTAssertTrue(url.contains("coordOutputFormat=EPSG:4326") || url.contains("coordOutputFormat=EPSG%3A4326"))
    }

    /// A coordinate origin needs type_origin=coord; sending it with the default "stop"
    /// fails on device only, after a Codemagic build and a TestFlight install.
    func testOriginTypeIsSentAsGiven() async throws {
        let client = TfNSWClient(session: StubFetcher(payload: Fixture.data("trip-sample")), keyProvider: { "k" })
        let request = try client.makeRequest(path: "trip", query: [
            URLQueryItem(name: "type_origin", value: "coord"),
            URLQueryItem(name: "name_origin", value: "151.180400:-33.796900:EPSG:4326"),
        ])
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("type_origin=coord"))
    }

    func testMissingKeyIsItsOwnError() async {
        let client = TfNSWClient(session: StubFetcher(), keyProvider: { nil })
        do {
            _ = try await client.journeys(originID: "1", destinationID: "2", departing: Date())
            XCTFail("expected missingKey")
        } catch let error as TfNSWError {
            XCTAssertEqual(error, .missingKey)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testUnauthorisedIsDistinctFromOtherFailures() async {
        let client = TfNSWClient(session: StubFetcher(status: 401), keyProvider: { "bad" })
        do {
            _ = try await client.journeys(originID: "1", destinationID: "2", departing: Date())
            XCTFail("expected unauthorised")
        } catch let error as TfNSWError {
            XCTAssertEqual(error, .unauthorised)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testJourneysDecodeFromAStubbedResponse() async throws {
        let client = TfNSWClient(
            session: StubFetcher(payload: Fixture.data("trip-sample")), keyProvider: { "k" }
        )
        let journeys = try await client.journeys(originID: "1", destinationID: "2", departing: Date())
        XCTAssertFalse(journeys.isEmpty)
        XCTAssertFalse(journeys[0].legs.isEmpty)
    }

    func testStopSuggestionsAreRankedBestFirst() async throws {
        let client = TfNSWClient(
            session: StubFetcher(payload: Fixture.data("stopfinder-sample")), keyProvider: { "k" }
        )
        let stops = try await client.findStops(matching: "Chatswood")
        XCTAssertFalse(stops.isEmpty)
        if let firstBest = stops.firstIndex(where: { $0.isBest }) {
            XCTAssertEqual(firstBest, 0, "the API's own best match must sort first")
        }
        XCTAssertFalse(stops.contains { $0.name.isEmpty })
    }
}
```

- [ ] **Step 5: Write `Storage/Feedback.swift`**

```swift
import Foundation

struct PredictionFeedback: Codable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let wasCorrect: Bool
    let mode: String
    let route: String?
    let originName: String
    let destinationName: String
    let plannedDeparture: Date?
    let estimatedDeparture: Date?
    let hadRealtime: Bool
    /// Tap time minus the time the app predicted. Positive means the app was early.
    let errorSeconds: Int?
}

extension PredictionFeedback {
    init(leg: Leg, wasCorrect: Bool, tappedAt: Date) {
        self.init(
            id: UUID(),
            recordedAt: tappedAt,
            wasCorrect: wasCorrect,
            mode: leg.mode.displayName,
            route: leg.route,
            originName: leg.originName,
            destinationName: leg.destinationName,
            plannedDeparture: leg.plannedDeparture,
            estimatedDeparture: leg.estimatedDeparture,
            hadRealtime: leg.hasRealtime,
            errorSeconds: leg.departure.map { Int(tappedAt.timeIntervalSince($0)) }
        )
    }
}
```

- [ ] **Step 6: Write `Storage/LocalStore.swift`**

```swift
import Foundation

/// One JSON file in Documents. Not SwiftData: this holds tens of rows of personal data with
/// no relationships and no queries, and a model container would be more moving parts than
/// the whole feature.
final class LocalStore: ObservableObject {
    private struct Contents: Codable {
        var recents: [StopSuggestion] = []
        var saved: [StopSuggestion] = []
        var feedback: [PredictionFeedback] = []
    }

    private static let recentsLimit = 10

    static let shared = LocalStore(
        fileURL: FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nextstop-store.json")
    )

    private let fileURL: URL
    private var contents: Contents { didSet { publish(); persist() } }

    @Published private(set) var recents: [StopSuggestion] = []
    @Published private(set) var saved: [StopSuggestion] = []
    @Published private(set) var feedback: [PredictionFeedback] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        // A corrupt or absent file starts empty rather than throwing. Losing a recents list
        // is not worth refusing to launch over. `didSet` does not fire in init, so this
        // load does not immediately write back.
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder.tfnswDecoder.decode(Contents.self, from: $0) }
        self.contents = loaded ?? Contents()
        publish()
    }

    func addRecent(_ stop: StopSuggestion) {
        var next = contents.recents.filter { $0.id != stop.id }
        next.insert(stop, at: 0)
        contents.recents = Array(next.prefix(Self.recentsLimit))
    }

    func toggleSaved(_ stop: StopSuggestion) {
        if let index = contents.saved.firstIndex(where: { $0.id == stop.id }) {
            contents.saved.remove(at: index)
        } else {
            contents.saved.append(stop)
        }
    }

    func isSaved(_ stop: StopSuggestion) -> Bool {
        contents.saved.contains { $0.id == stop.id }
    }

    func record(_ item: PredictionFeedback) {
        contents.feedback.append(item)
    }

    func exportFeedbackJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(contents.feedback)
    }

    private func publish() {
        recents = contents.recents
        saved = contents.saved
        feedback = contents.feedback
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(contents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 7: Write `ios/Tests/LocalStoreTests.swift`**

```swift
import XCTest
@testable import NextStop

final class LocalStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func suggestion(_ id: String) -> StopSuggestion {
        StopSuggestion(id: id, name: "Stop \(id)", isBest: false)
    }

    func testRecentsAreMostRecentFirstAndDeduplicated() {
        let store = LocalStore(fileURL: url)
        store.addRecent(suggestion("a"))
        store.addRecent(suggestion("b"))
        store.addRecent(suggestion("a"))
        XCTAssertEqual(store.recents.map(\.id), ["a", "b"])
    }

    func testRecentsAreCappedAtTen() {
        let store = LocalStore(fileURL: url)
        for index in 0..<15 { store.addRecent(suggestion("\(index)")) }
        XCTAssertEqual(store.recents.count, 10)
        XCTAssertEqual(store.recents.first?.id, "14")
    }

    func testSavedTogglesBothWays() {
        let store = LocalStore(fileURL: url)
        store.toggleSaved(suggestion("a"))
        XCTAssertTrue(store.isSaved(suggestion("a")))
        store.toggleSaved(suggestion("a"))
        XCTAssertFalse(store.isSaved(suggestion("a")))
    }

    func testEverythingSurvivesAReload() throws {
        let store = LocalStore(fileURL: url)
        store.addRecent(suggestion("a"))
        store.toggleSaved(suggestion("b"))
        store.record(PredictionFeedback(
            id: UUID(), recordedAt: Date(), wasCorrect: false, mode: "Bus", route: "412",
            originName: "Railway Square", destinationName: "USyd",
            plannedDeparture: nil, estimatedDeparture: nil, hadRealtime: true, errorSeconds: 120
        ))

        let reloaded = LocalStore(fileURL: url)
        XCTAssertEqual(reloaded.recents.map(\.id), ["a"])
        XCTAssertEqual(reloaded.saved.map(\.id), ["b"])
        XCTAssertEqual(reloaded.feedback.count, 1)
        XCTAssertEqual(reloaded.feedback[0].errorSeconds, 120)
    }

    /// A tap is worth more than a verdict: the gap between the predicted departure and the
    /// moment the user tapped is the measurable error.
    func testFeedbackFromALegComputesErrorAgainstTheTapTime() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let leg = Leg(
            id: "test", mode: .bus, route: "412", headsign: "USyd",
            originName: "Railway Square", destinationName: "USyd",
            plannedDeparture: planned, estimatedDeparture: planned.addingTimeInterval(60),
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: 600
        )
        let feedback = PredictionFeedback(leg: leg, wasCorrect: true, tappedAt: planned.addingTimeInterval(150))
        XCTAssertEqual(feedback.errorSeconds, 90)
        XCTAssertEqual(feedback.mode, "Bus")
        XCTAssertTrue(feedback.hadRealtime)
    }

    func testExportIsDecodableJSON() throws {
        let store = LocalStore(fileURL: url)
        store.record(PredictionFeedback(
            id: UUID(), recordedAt: Date(), wasCorrect: true, mode: "Metro", route: "M1",
            originName: "Chatswood", destinationName: "Central",
            plannedDeparture: nil, estimatedDeparture: nil, hadRealtime: true, errorSeconds: 0
        ))
        let decoded = try JSONDecoder.tfnswDecoder.decode(
            [PredictionFeedback].self, from: try store.exportFeedbackJSON()
        )
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].mode, "Metro")
    }
}
```

- [ ] **Step 8: Commit and push**

```bash
git add ios/Sources/App/Storage ios/Sources/App/TfNSW/TfNSWClient.swift ios/Tests
git commit -m "Add Keychain storage, the TfNSW client, and the local store"
git push
```

Expected: `KeychainStoreTests` (2), `TfNSWClientTests` (6), `LocalStoreTests` (6) pass alongside the earlier suites. `.iso8601` must be set on both encode and decode or `testEverythingSurvivesAReload` fails on the date.

---

### Task 5 — PUSH 4: Map, status, location, and app state

Everything with logic worth testing, before any view bodies.

**Files:**
- Create: `ios/Sources/App/Map/JourneyMapView.swift`, `ios/Sources/App/UI/DepartureStatus.swift`, `ios/Sources/App/LocationProvider.swift`, `ios/Sources/App/AppModel.swift`
- Test: `ios/Tests/MapRegionTests.swift`, `ios/Tests/DepartureStatusTests.swift`, `ios/Tests/LocationProviderTests.swift`, `ios/Tests/AppModelTests.swift`

**Interfaces:**
- Produces:
  - `enum MapFraming { static func region(for: Journey, padding: Double = 1.4) -> MKCoordinateRegion? }`
  - `struct JourneyMapView: View { init(journey: Journey?) }`
  - `enum DepartureStatus: Equatable { case onTime, late(Int), early(Int), scheduledOnly; init(leg:); var label: String; var tint: Color }`
  - `@MainActor final class LocationProvider: NSObject, ObservableObject` — `coordinate`, `authorisation`, `requestWhenInUse()`, `start()`, `stop()`, `static func tfnswOriginString(for:) -> String`
  - `@MainActor final class AppModel: ObservableObject` — `store`, `location`, `destination`, `journeys`, `selectedJourneyID: String?`, `searchResults`, `searchError`, `phase: Phase`, `selectedJourney`, `originID`/`originType`, `search(_:)`, `plan(to:)`, `refresh()`, `reset()`
  - `enum Phase: Equatable { case idle, planning, ready, failed(TfNSWError) }`

- [ ] **Step 1: Write `Map/JourneyMapView.swift`**

```swift
import MapKit
import SwiftUI

enum MapFraming {
    /// Below this the map shows a single blank tile at maximum zoom, which reads as a
    /// broken map rather than a short walk.
    private static let minimumSpan: CLLocationDegrees = 0.005

    static func region(for journey: Journey, padding: Double = 1.4) -> MKCoordinateRegion? {
        let points = journey.legs.flatMap(\.path)
        guard let first = points.first else { return nil }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * padding, minimumSpan),
                longitudeDelta: max((maxLon - minLon) * padding, minimumSpan)
            )
        )
    }
}

struct JourneyMapView: View {
    let journey: Journey?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            if let journey {
                ForEach(journey.legs) { leg in
                    MapPolyline(coordinates: leg.path)
                        .stroke(
                            leg.mode.tint,
                            style: StrokeStyle(
                                lineWidth: leg.mode.isWalking ? 4 : 7,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: leg.mode.isWalking ? [2, 8] : []
                            )
                        )
                }
                ForEach(journey.transitLegs) { leg in
                    if let start = leg.path.first {
                        Annotation(leg.originName, coordinate: start) { interchangeDot(leg.mode) }
                    }
                }
                if let final = journey.legs.last, let end = final.path.last {
                    Annotation(final.destinationName, coordinate: end) { interchangeDot(final.mode) }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .preferredColorScheme(.dark)
        .onChange(of: journey?.id) { _, _ in frame() }
        .onAppear { frame() }
    }

    private func interchangeDot(_ mode: TransitMode) -> some View {
        Circle()
            .fill(Theme.Colors.background)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(mode.tint, lineWidth: 4))
            .shadow(color: .black.opacity(0.4), radius: 3)
    }

    private func frame() {
        guard let journey, let region = MapFraming.region(for: journey) else { return }
        withAnimation(.easeInOut(duration: 0.6)) { position = .region(region) }
    }
}
```

- [ ] **Step 2: Write `UI/DepartureStatus.swift`**

```swift
import SwiftUI

enum DepartureStatus: Equatable {
    case onTime
    case late(Int)
    case early(Int)
    case scheduledOnly

    /// A minute of slack either way. TfNSW estimates jitter by seconds constantly, and a
    /// "1 min late" that flips back a moment later reads as a broken app.
    private static let tolerance: TimeInterval = 60

    init(leg: Leg) {
        guard leg.hasRealtime, let delay = leg.delaySeconds else {
            self = .scheduledOnly
            return
        }
        let seconds = Double(delay)
        if abs(seconds) <= Self.tolerance {
            self = .onTime
        } else if seconds > 0 {
            self = .late(Int((seconds / 60).rounded()))
        } else {
            self = .early(Int((-seconds / 60).rounded()))
        }
    }

    var label: String {
        switch self {
        case .onTime: "On time"
        case .late(let minutes): "\(minutes) min late"
        case .early(let minutes): "\(minutes) min early"
        case .scheduledOnly: "Scheduled only"
        }
    }

    var tint: Color {
        switch self {
        case .onTime: Theme.Colors.onTime
        case .late(let minutes): minutes >= 5 ? Theme.Colors.veryLate : Theme.Colors.late
        case .early: Theme.Colors.late
        case .scheduledOnly: Theme.Colors.noRealtime
        }
    }
}
```

- [ ] **Step 3: Write `LocationProvider.swift`**

`super.init()` comes first. Reading `manager.authorizationStatus` before it is a phase-1 violation and will not compile.

```swift
import CoreLocation

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorisation: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorisation = manager.authorizationStatus
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }

    /// EFA wants longitude before latitude here, unlike the `coords` arrays it returns.
    /// Six decimal places is roughly 0.1 m — more than enough, and shorter than the default
    /// description, which can render in scientific notation.
    static func tfnswOriginString(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f:%.6f:EPSG:4326", coordinate.longitude, coordinate.latitude)
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in self.coordinate = last.coordinate }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorisation = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.start()
            }
        }
    }
}
```

- [ ] **Step 4: Write `AppModel.swift`**

Two things here are load-bearing and easy to get wrong:

`departAt` is pinned once per destination. If `refresh()` re-planned with `Date()`, then five minutes into a bus ride TfNSW would return a *different set of journeys* — the leg being ridden disappears, the countdown resets, and the feedback buttons vanish before they can be tapped.

`search` never writes `phase`. Sharing one phase between search and planning means every keystroke clears the plan's error banner.

```swift
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle, planning, ready
        case failed(TfNSWError)
    }

    /// Below this the Stop Finder returns most of Sydney and the list is useless.
    private static let minimumQueryLength = 3

    let store: LocalStore
    let location = LocationProvider()
    private let client: TfNSWClient

    @Published var destination: StopSuggestion?
    @Published var journeys: [Journey] = []
    @Published var selectedJourneyID: String?
    @Published var searchResults: [StopSuggestion] = []
    @Published var searchError: TfNSWError?
    @Published var phase: Phase = .idle

    private var departAt: Date?

    init(client: TfNSWClient = TfNSWClient(), store: LocalStore = .shared) {
        self.client = client
        self.store = store
    }

    var selectedJourney: Journey? {
        journeys.first { $0.id == selectedJourneyID }
    }

    /// Falls back to Chatswood rather than refusing to plan. A journey from the wrong origin
    /// is visible and correctable; a blank screen tells the user nothing.
    var originID: String {
        location.coordinate.map(LocationProvider.tfnswOriginString(for:)) ?? "10101100"
    }

    var originType: String {
        location.coordinate == nil ? "stop" : "coord"
    }

    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minimumQueryLength else {
            searchResults = []
            searchError = nil
            return
        }
        do {
            searchResults = try await client.findStops(matching: query)
            searchError = nil
        } catch let error as TfNSWError {
            searchResults = []
            searchError = error
        } catch {
            searchResults = []
            searchError = .transport
        }
    }

    func plan(to stop: StopSuggestion) async {
        destination = stop
        departAt = Date()
        selectedJourneyID = nil
        phase = .planning
        await load(recordRecent: true)
    }

    /// Re-plans against the pinned departure time, keeping the user's selected option if it
    /// is still in the result. Called on a timer while the journey screen is open.
    func refresh() async {
        guard destination != nil else { return }
        await load(recordRecent: false)
    }

    func reset() {
        destination = nil
        journeys = []
        selectedJourneyID = nil
        searchResults = []
        searchError = nil
        departAt = nil
        phase = .idle
    }

    private func load(recordRecent: Bool) async {
        guard let destination, let departAt else { return }
        do {
            let found = try await client.journeys(
                originID: originID,
                originType: originType,
                destinationID: destination.id,
                departing: departAt
            )
            journeys = found
            if selectedJourneyID == nil || !found.contains(where: { $0.id == selectedJourneyID }) {
                selectedJourneyID = found.first?.id
            }
            if recordRecent { store.addRecent(destination) }
            phase = .ready
        } catch let error as TfNSWError {
            journeys = []
            selectedJourneyID = nil
            phase = .failed(error)
        } catch {
            journeys = []
            selectedJourneyID = nil
            phase = .failed(.transport)
        }
    }
}
```

- [ ] **Step 5: Write the four test files**

`ios/Tests/MapRegionTests.swift`:

```swift
import CoreLocation
import MapKit
import XCTest
@testable import NextStop

final class MapRegionTests: XCTestCase {
    private func journey() throws -> Journey {
        let dto = try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
        return try XCTUnwrap(Journey.list(from: dto).first)
    }

    private func walkLeg(path: [CLLocationCoordinate2D]) -> Leg {
        Leg(
            id: "w", mode: .walk, route: nil, headsign: nil,
            originName: "A", destinationName: "B",
            plannedDeparture: nil, estimatedDeparture: nil,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: false, path: path, stops: [], durationSeconds: 60
        )
    }

    func testRegionContainsEveryPointOnTheRoute() throws {
        let journey = try journey()
        let region = try XCTUnwrap(MapFraming.region(for: journey))
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        for leg in journey.legs {
            for point in leg.path {
                XCTAssertTrue((minLat...maxLat).contains(point.latitude))
                XCTAssertTrue((minLon...maxLon).contains(point.longitude))
            }
        }
    }

    /// A journey between two stops a few hundred metres apart must not produce a span so
    /// small the map renders at maximum zoom on a blank tile.
    func testRegionHasAMinimumSpan() {
        let point = CLLocationCoordinate2D(latitude: -33.7969, longitude: 151.1804)
        let region = MapFraming.region(for: Journey(id: "j", legs: [walkLeg(path: [point, point])]))
        XCTAssertNotNil(region)
        XCTAssertGreaterThanOrEqual(region!.span.latitudeDelta, 0.005)
    }

    func testJourneyWithNoGeometryHasNoRegion() {
        XCTAssertNil(MapFraming.region(for: Journey(id: "j", legs: [walkLeg(path: [])])))
    }
}
```

`ios/Tests/DepartureStatusTests.swift`:

```swift
import XCTest
@testable import NextStop

final class DepartureStatusTests: XCTestCase {
    private func leg(planned: Date?, estimated: Date?, realtime: Bool) -> Leg {
        Leg(
            id: "test", mode: .bus, route: "412", headsign: "USyd",
            originName: "A", destinationName: "B",
            plannedDeparture: planned, estimatedDeparture: estimated,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: realtime, path: [], stops: [], durationSeconds: 600
        )
    }

    /// Untracked is not the same as on time. Claiming a service is punctual when nobody is
    /// watching it is the exact dishonesty this app exists to avoid.
    func testNoRealtimeIsScheduledOnlyRatherThanOnTime() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: nil, realtime: false))
        XCTAssertEqual(status, .scheduledOnly)
        XCTAssertEqual(status.tint, Theme.Colors.noRealtime)
    }

    func testRealtimeFlagFalseIsScheduledOnlyEvenWithAnEstimate() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(300), realtime: false))
        XCTAssertEqual(status, .scheduledOnly)
    }

    func testWithinAMinuteCountsAsOnTime() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(30), realtime: true)), .onTime)
    }

    func testLateIsReportedInWholeMinutes() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(185), realtime: true))
        XCTAssertEqual(status, .late(3))
        XCTAssertEqual(status.label, "3 min late")
    }

    func testEarlyIsReportedSeparately() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(-150), realtime: true))
        XCTAssertEqual(status, .early(2))
        XCTAssertEqual(status.label, "2 min early")
    }
}
```

`ios/Tests/LocationProviderTests.swift`:

```swift
import CoreLocation
import XCTest
@testable import NextStop

final class LocationProviderTests: XCTestCase {
    /// The Trip Planner takes a coordinate origin as "longitude:latitude:EPSG:4326" —
    /// longitude first, the opposite order to everything else in this codebase.
    func testCoordinateOriginIsLongitudeFirst() {
        let coordinate = CLLocationCoordinate2D(latitude: -33.7969, longitude: 151.1804)
        XCTAssertEqual(
            LocationProvider.tfnswOriginString(for: coordinate),
            "151.180400:-33.796900:EPSG:4326"
        )
    }
}
```

`ios/Tests/AppModelTests.swift` — note `StubFetcher` is declared once, in `TfNSWClientTests.swift`, and reused here:

```swift
import XCTest
@testable import NextStop

@MainActor
final class AppModelTests: XCTestCase {
    private func model(status: Int = 200, payload: Data = Data()) -> AppModel {
        AppModel(
            client: TfNSWClient(session: StubFetcher(status: status, payload: payload), keyProvider: { "k" }),
            store: LocalStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).json"))
        )
    }

    private let usyd = StopSuggestion(id: "2", name: "USyd", isBest: true)

    func testPlanningPopulatesJourneysAndSelectsTheFirst() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.journeys.isEmpty)
        XCTAssertEqual(model.selectedJourneyID, model.journeys.first?.id)
        XCTAssertNotNil(model.selectedJourney)
    }

    func testPlanningRecordsTheDestinationAsRecent() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        XCTAssertEqual(model.store.recents.first?.id, "2")
    }

    /// The user's chosen option must survive a refresh, and a refresh must not append a
    /// duplicate recent every 30 seconds.
    func testRefreshKeepsTheSelectionAndDoesNotDuplicateRecents() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        let chosen = model.journeys.last?.id
        model.selectedJourneyID = chosen
        await model.refresh()
        XCTAssertEqual(model.selectedJourneyID, chosen)
        XCTAssertEqual(model.store.recents.count, 1)
    }

    func testAnUnauthorisedPlanSurfacesTheError() async {
        let model = model(status: 401)
        await model.plan(to: usyd)
        XCTAssertEqual(model.phase, .failed(.unauthorised))
        XCTAssertTrue(model.journeys.isEmpty)
    }

    func testShortQueriesDoNotSearch() async {
        let model = model(payload: Fixture.data("stopfinder-sample"))
        await model.search("Ch")
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    func testSearchPopulatesResults() async {
        let model = model(payload: Fixture.data("stopfinder-sample"))
        await model.search("Chatswood")
        XCTAssertFalse(model.searchResults.isEmpty)
    }

    /// Search and planning must not share error state, or a keystroke wipes the banner
    /// telling the user their key was rejected.
    func testSearchDoesNotClearAPlanFailure() async {
        let model = model(status: 401)
        await model.plan(to: usyd)
        await model.search("Ch")
        XCTAssertEqual(model.phase, .failed(.unauthorised))
    }

    func testResetClearsEverything() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        model.reset()
        XCTAssertTrue(model.journeys.isEmpty)
        XCTAssertNil(model.destination)
        XCTAssertEqual(model.phase, .idle)
    }
}
```

- [ ] **Step 6: Commit and push**

```bash
git add ios/Sources/App/Map ios/Sources/App/UI/DepartureStatus.swift ios/Sources/App/LocationProvider.swift ios/Sources/App/AppModel.swift ios/Tests
git commit -m "Add map framing, departure status, location, and app state"
git push
```

Expected: `MapRegionTests` (3), `DepartureStatusTests` (5), `LocationProviderTests` (1), `AppModelTests` (8) pass alongside the earlier suites.

- [x] **Step 7: Confirm the fallback origin ID** — done, the guess was wrong.

The plan guessed `"10101100"`. `stop_finder` returns **`206710`** for Chatswood Station. Corrected as `AppModel.fallbackOriginID`. The command that established it:

```bash
cd collector && uv run python -c "
from nextstop_collector.tfnsw.client import TfnswClient
from nextstop_collector.tfnsw.stops import find_candidates
with TfnswClient() as c:
    print(find_candidates(c, 'Chatswood Station', limit=1))
"
```

---

### Task 6 — PUSH 5: Every screen, the root, and CI screenshots

All view bodies land together. `HomeView` links to `LiveJourneyView` and `SettingsView`, so splitting them means a push that can only fail.

No unit tests here: these are view bodies, and a snapshot test of CI-rendered glass costs more to maintain than it catches. The gate is the compile plus the screenshots.

**Files:**
- Create: `ios/Sources/App/UI/GlassCard.swift`, `UI/LegRow.swift`, `UI/SearchSheet.swift`, `UI/JourneyOptionsView.swift`, `UI/HomeView.swift`, `UI/LiveJourneyView.swift`, `UI/SettingsView.swift`
- Modify: `ios/Sources/App/NextStopApp.swift:21-40`, `.github/workflows/ios-compile.yml`

**Interfaces:**
- `LocalStore` is injected as **its own environment object**. It is a separate `ObservableObject` from `AppModel`, so a view observing only `model` is never invalidated when the store changes — the saved star would never toggle and the feedback count would never move.

- [ ] **Step 1: Write `UI/GlassCard.swift`**

```swift
import SwiftUI

extension View {
    /// Material rather than iOS 26's `glassEffect`: the CI simulator has rendered glass
    /// inconsistently, and the screenshots are the only way to see this UI before a device
    /// build exists. Revisit once there is a phone to compare against.
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Capsule()
                .fill(Theme.Colors.stroke)
                .frame(width: 36, height: 5)
            content
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .glassSurface()
        .padding(.horizontal, Theme.Spacing.s)
    }
}
```

- [ ] **Step 2: Write `UI/LegRow.swift`**

```swift
import SwiftUI

struct LegRow: View {
    let leg: Leg
    let isNext: Bool
    let now: Date
    var onFeedback: ((Bool) -> Void)?

    private var status: DepartureStatus { DepartureStatus(leg: leg) }

    private var minutesAway: Int? {
        guard let departure = leg.departure else { return nil }
        let seconds = departure.timeIntervalSince(now)
        return seconds < -60 ? nil : Int((seconds / 60).rounded())
    }

    private var hasDeparted: Bool {
        guard let departure = leg.departure else { return false }
        return now > departure
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(spacing: 0) {
                Image(systemName: leg.mode.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(leg.mode.isWalking ? Theme.Colors.textSecondary : .white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(leg.mode.tint.opacity(leg.mode.isWalking ? 0.15 : 1)))
                Rectangle()
                    .fill(leg.mode.tint.opacity(0.45))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(leg.route ?? leg.mode.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let headsign = leg.headsign, !leg.mode.isWalking {
                        Text(headsign)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if let minutes = minutesAway {
                        Text(minutes <= 0 ? "now" : "\(minutes) min")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(isNext ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .contentTransition(.numericText())
                    }
                }

                if leg.mode.isWalking {
                    Text("\(Int((leg.durationSeconds ?? 0) / 60)) min to \(leg.destinationName)")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("from \(leg.originName)")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.tint)
                }

                if hasDeparted, let onFeedback, !leg.mode.isWalking {
                    HStack(spacing: Theme.Spacing.s) {
                        Text("Was this right?")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Button { onFeedback(true) } label: { Label("Yes", systemImage: "checkmark") }
                        Button { onFeedback(false) } label: { Label("No", systemImage: "xmark") }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .tint(Theme.Colors.textSecondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .animation(.snappy, value: hasDeparted)
    }
}
```

- [ ] **Step 3: Write `UI/SearchSheet.swift`**

```swift
import SwiftUI

struct SearchSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.searchError {
                    Section {
                        Text(error == .missingKey || error == .unauthorised
                             ? "Add a valid Transport NSW API key in Settings."
                             : "Could not reach Transport NSW.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.late)
                    }
                }
                if !store.saved.isEmpty && text.isEmpty {
                    Section("Saved") { rows(store.saved) }
                }
                if !store.recents.isEmpty && text.isEmpty {
                    Section("Recent") { rows(store.recents) }
                }
                if !model.searchResults.isEmpty {
                    Section("Results") { rows(model.searchResults) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $text, prompt: "Station, stop, or address")
            .onChange(of: text) { _, new in schedule(new) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rows(_ stops: [StopSuggestion]) -> some View {
        ForEach(stops) { stop in
            Button {
                dismiss()
                Task { await model.plan(to: stop) }
            } label: {
                HStack {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.Colors.textSecondary)
                    Text(stop.name).foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if store.isSaved(stop) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
            }
            .swipeActions(edge: .leading) {
                Button(store.isSaved(stop) ? "Unsave" : "Save") { store.toggleSaved(stop) }
                    .tint(.yellow)
            }
        }
    }

    /// Debounced rather than fired per keystroke: the quota is 60k calls a day and a
    /// nine-letter station name would otherwise spend nine of them.
    private func schedule(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
    }
}
```

- [ ] **Step 4: Write `UI/JourneyOptionsView.swift`**

```swift
import SwiftUI

struct JourneyOptionsView: View {
    @EnvironmentObject private var model: AppModel

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: "Australia/Sydney")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(model.journeys) { journey in
                    card(journey)
                        .onTapGesture {
                            withAnimation(.snappy) { model.selectedJourneyID = journey.id }
                        }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
        .scrollClipDisabled()
    }

    private func card(_ journey: Journey) -> some View {
        let selected = journey.id == model.selectedJourneyID
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(journey.transitLegs.prefix(4)) { leg in
                    Text(leg.route ?? leg.mode.displayName)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(leg.mode.tint))
                        .foregroundStyle(.white)
                }
            }
            if let departure = journey.departure, let arrival = journey.arrival {
                Text("\(Self.clock.string(from: departure)) → \(Self.clock.string(from: arrival))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            if let duration = journey.duration {
                Text("\(Int(duration / 60)) min")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(width: 190, alignment: .leading)
        .glassSurface(cornerRadius: Theme.Radius.pill)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                .strokeBorder(selected ? Theme.Colors.textPrimary : .clear, lineWidth: 2)
        )
        .scaleEffect(selected ? 1 : 0.95)
        .animation(.snappy, value: selected)
    }
}
```

- [ ] **Step 5: Write `UI/HomeView.swift`**

```swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showingSettings: Bool
    @State private var showingSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            JourneyMapView(journey: model.selectedJourney)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.m) {
                if !model.journeys.isEmpty {
                    JourneyOptionsView()
                }
                GlassCard {
                    if let destination = model.destination, model.selectedJourney != nil {
                        NavigationLink {
                            LiveJourneyView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("To \(destination.name)")
                                        .font(.headline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("Tap for live times")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    } else {
                        Button { showingSearch = true } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Where to?")
                                Spacer()
                            }
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.vertical, Theme.Spacing.s)
                        }
                    }

                    if case .planning = model.phase {
                        ProgressView().tint(Theme.Colors.textSecondary)
                    }
                    if case .failed(let error) = model.phase {
                        errorRow(error)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.s)
        }
        // Without an inline title the map sits under an empty large-title bar, which reads
        // as an unfinished screen in the CI screenshot.
        .navigationTitle("NextStop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarLeading) {
                if model.destination != nil {
                    Button("Clear") { withAnimation(.snappy) { model.reset() } }
                }
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchSheet()
                .environmentObject(model)
                .environmentObject(model.store)
        }
        .onAppear {
            model.location.requestWhenInUse()
            model.location.start()
        }
        .onDisappear { model.location.stop() }
    }

    @ViewBuilder
    private func errorRow(_ error: TfNSWError) -> some View {
        let message: String = switch error {
        case .missingKey: "Add your Transport NSW API key in Settings"
        case .unauthorised: "That API key was rejected. Check it in Settings."
        case .http(let code): "Transport NSW returned an error (\(code))"
        case .transport: "Could not reach Transport NSW"
        }
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.footnote)
            Spacer()
            if error == .missingKey || error == .unauthorised {
                Button("Settings") { showingSettings = true }.font(.footnote.weight(.semibold))
            }
        }
        .foregroundStyle(Theme.Colors.late)
    }
}
```

- [ ] **Step 6: Write `UI/LiveJourneyView.swift`**

```swift
import SwiftUI

struct LiveJourneyView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: LocalStore

    @State private var now = Date()
    @State private var recorded: Set<String> = []
    @State private var lastRefresh = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// The realtime feed itself only moves every 10–15 seconds, so anything faster than this
    /// spends quota to redraw the same numbers.
    private let refreshEvery: TimeInterval = 30

    var body: some View {
        ZStack(alignment: .bottom) {
            JourneyMapView(journey: model.selectedJourney)
                .ignoresSafeArea()

            if let journey = model.selectedJourney {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(journey)
                        ForEach(Array(journey.legs.enumerated()), id: \.element.id) { index, leg in
                            LegRow(
                                leg: leg,
                                isNext: index == nextLegIndex(journey),
                                now: now,
                                onFeedback: recorded.contains(leg.id) ? nil : { record(leg, $0) }
                            )
                        }
                    }
                    .padding(Theme.Spacing.m)
                    .glassSurface()
                    .padding(Theme.Spacing.s)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 460)
            }
        }
        .navigationTitle(model.destination?.name ?? "Journey")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { instant in
            now = instant
            if instant.timeIntervalSince(lastRefresh) >= refreshEvery {
                lastRefresh = instant
                Task { await model.refresh() }
            }
        }
    }

    private func header(_ journey: Journey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let arrival = journey.arrival {
                Text("Arrive \(arrival.formatted(date: .omitted, time: .shortened))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            if let duration = journey.duration {
                let count = journey.transitLegs.count
                Text("\(Int(duration / 60)) min · \(count) service\(count == 1 ? "" : "s")")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    private func nextLegIndex(_ journey: Journey) -> Int? {
        journey.legs.firstIndex { ($0.departure ?? .distantPast) > now }
    }

    private func record(_ leg: Leg, _ wasCorrect: Bool) {
        store.record(PredictionFeedback(leg: leg, wasCorrect: wasCorrect, tappedAt: Date()))
        withAnimation(.snappy) { _ = recorded.insert(leg.id) }
    }
}
```

- [ ] **Step 7: Write `UI/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var hasKey = KeychainStore.read() != nil
    @State private var exported: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste your key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        try? KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                        hasKey = KeychainStore.read() != nil
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey {
                        Label("A key is stored on this device", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.Colors.onTime)
                    }
                } header: {
                    Text("Transport NSW API key")
                } footer: {
                    Text("Free from opendata.transport.nsw.gov.au. Stored in the iOS Keychain and sent only to Transport NSW.")
                }

                Section("Feedback") {
                    LabeledContent("Recorded", value: "\(store.feedback.count)")
                    if let exported {
                        ShareLink("Export as JSON", item: exported)
                    }
                }

                Section("Developer") {
                    NavigationLink("Live Activity spike") { SpikeControlView() }
                    NavigationLink("Live Activity layouts") { ActivityHarnessView() }
                    NavigationLink("Debug log") { DebugLogView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: writeExport)
        }
        .preferredColorScheme(.dark)
    }

    /// ShareLink needs a file that already exists, so the export is written when the screen
    /// appears rather than when the user taps.
    private func writeExport() {
        guard !store.feedback.isEmpty, let data = try? store.exportFeedbackJSON() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nextstop-feedback.json")
        try? data.write(to: url, options: .atomic)
        exported = url
    }
}
```

- [ ] **Step 8: Rewrite `RootView` in `ios/Sources/App/NextStopApp.swift`**

Replace lines 21–40. Leave `@main struct NextStopApp` above it untouched.

The settings sheet is a real `@State` binding, not `.constant(...)` — with a constant binding the Done button dismisses and the sheet immediately re-presents. It opens automatically when no key is stored, which is otherwise a dead end: the user taps "Where to?", types, gets `.missingKey`, and sees an empty list with the error banner hidden behind the sheet.

`SpikeSession` is re-injected explicitly. `SpikeControlView.swift:5` uses `@Environment(SpikeSession.self)`, which traps when absent, and the developer menu lives inside this sheet.

```swift
struct RootView: View {
    @Environment(SpikeSession.self) private var session
    @StateObject private var model = AppModel()
    @State private var showingSettings: Bool

    init() {
        // CI launches with `-initialScreen settings` to screenshot a screen it cannot
        // otherwise reach. UserDefaults picks launch arguments up via NSArgumentDomain.
        let requested = UserDefaults.standard.string(forKey: "initialScreen") == "settings"
        _showingSettings = State(initialValue: requested || KeychainStore.read() == nil)
    }

    var body: some View {
        NavigationStack {
            HomeView(showingSettings: $showingSettings)
                .background(Theme.Colors.background)
        }
        .environmentObject(model)
        .environmentObject(model.store)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.textPrimary)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environment(session)
        }
    }
}
```

- [ ] **Step 9: Update the CI screenshot step**

In `.github/workflows/ios-compile.yml`, replace the `for tab in spike layouts log` loop body with:

```bash
          UDID="${{ steps.sim.outputs.udid }}"
          xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/NextStop.app
          mkdir -p shots
          for screen in home settings; do
            xcrun simctl terminate "$UDID" com.kaichuan.nextstop 2>/dev/null || true
            sleep 3
            echo "--- launching $screen ---"
            xcrun simctl launch "$UDID" com.kaichuan.nextstop -initialScreen "$screen"
            # A blank first screenshot suggested the launch screen was still up, so give
            # SwiftUI real time rather than guessing again.
            sleep 15
            xcrun simctl io "$UDID" screenshot "shots/$screen.png"
          done
          ls -la shots
```

The spike screens leave CI screenshot coverage with this change. That is accepted — they are verified on a real phone — but a regression in them will no longer be caught automatically.

- [ ] **Step 10: Commit and push**

```bash
git add ios/Sources/App/UI ios/Sources/App/NextStopApp.swift .github/workflows/ios-compile.yml
git commit -m "Wire the journey app as the root screen"
git push
```

Expected: build succeeds, every test passes, and `simulator-screenshots` contains `home.png` and `settings.png`.

- [ ] **Step 11: Download the artifact and look at both screenshots**

This is the only visual check that exists before a device build. A white background means `preferredColorScheme` is not reaching a sheet. A blank grey rectangle where the map should be is expected in a simulator with no location fix and is not a failure. An empty bar above the map means Step 5's title modifiers did not take.

---

### Task 7: Use it

- [ ] **Step 1: Build and install**

Push to `main`, let Codemagic build, install from TestFlight. Open Settings, paste the TfNSW key.

- [ ] **Step 2: The real gate**

Plan a journey to somewhere you have not been. Follow it. Tap ✓ or ✗ on each leg as it departs. Export the feedback from Settings afterwards.

What to watch for, in order of likelihood:
1. Does the leg list stay still, or does it flicker every 30 seconds? (Stable ids — Task 3 Step 7.)
2. Does the journey you selected stay selected across refreshes? (Pinned `departAt` — Task 5 Step 4.)
3. Do the "Was this right?" buttons stay tapped once tapped?
4. Does the map draw the route, or straight lines between stops?
5. Are the mode colours right for bus? (Task 3 Step 10.)

---

## Deliberately Not In This Plan

- **Live Activity for real journeys.** The spike works on device; wiring it to `Journey` is a follow-up once there is a fortnight of using the app to say what belongs on a Lock Screen.
- **The VPS proxy.** Needed the day a second person installs this, because nobody else will type in an API key. `deploy/nextstop-api.service` already exists for it.
- **Porting the collector's quirk filters to Swift.** They operate on raw GTFS-Realtime feeds; the Trip Planner endpoint this app uses returns estimated times directly.
- **Rate limiting in the app.** The collector needs a token bucket because it runs unattended. One person tapping a phone cannot approach 60,000 calls a day.
- **Offline caching.** Every screen needs live data to be worth anything.
- **Snapshot tests of the UI.** The CI screenshots are the check.
- **An App Transport Security exception.** `api.transport.nsw.gov.au` is HTTPS with TLS 1.2+; adding an exception dictionary would only weaken the default.
