# NextStop v1 — Journey App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the NextStop iOS spike into an app that plans a journey to anywhere in NSW, shows live departure times with an honest indication of whether they are real, draws the route properly on a map, and lets the user mark each prediction right or wrong.

**Architecture:** A native SwiftUI app talking directly to the TfNSW Trip Planner v1 API — `stop_finder` for destination search, `trip` for routing. No backend. The API key is entered once in Settings and stored in the iOS Keychain. MapKit renders per-leg polylines from the `coords` array TfNSW already returns. Recents, saved places, and prediction feedback are stored as a JSON file in the app's Documents directory.

**Tech Stack:** Swift 5 language mode, SwiftUI, MapKit, Foundation `URLSession`, XCTest. XcodeGen generates the project. Python 3.13 + Typer + SQLAlchemy for the one collector task.

## Global Constraints

- **Deployment target iOS 26.0**, `SWIFT_VERSION = 5.0`. Both are set in `ios/project.yml` and must not change.
- **There is no Mac and no local Swift toolchain.** Every Swift test and build runs on GitHub Actions (`macos-latest`). The edit→result loop is roughly 5 minutes, not 5 seconds. Batch work accordingly and never write a step that assumes local `xcodebuild`.
- **Python tests do run locally on Windows** via `uv run pytest` from `collector/`. Task 1 is the only task with a fast loop.
- **The TfNSW API key must never enter the repo, CI, or the app binary.** Keychain only, entered by the user at runtime. This is a hard floor with no exceptions.
- **Google Maps Platform APIs are forbidden as a data source.** MapKit only. Google Maps remains a visual design reference and nothing more.
- **The repo is private** because `PROJECT_BRIEF.md`, `collector/README.md`, and `collector/src/nextstop_collector/watchlist.py` contain a home address. Do not make it public.
- **Do not break the Live Activity spike.** `SpikeControlView`, `ActivityHarnessView`, `DebugLogView`, `SpikeSession`, `LiveActivityController`, and everything under `Sources/Widget` are working code that has been verified on a real iPhone. They move behind a developer menu; they are not deleted or edited.
- **Design language:** dark theme, glass surfaces, real motion. No flat white cards, no static information dumps. Colours and sizes come from tokens in `Theme.swift`, never hardcoded at call sites.
- **Comment style:** comment the *why*, never the *what*. Match the density of the surrounding file. Existing files in this repo have sparse, high-value comments — follow that.

---

## File Structure

**New Swift source, all under `ios/Sources/App/`:**

| Path | Responsibility |
| --- | --- |
| `Theme.swift` | Colour, spacing, and typography tokens. Single source for TfNSW mode colours. |
| `TfNSW/TransitMode.swift` | TfNSW product class → mode enum, display name, colour, SF Symbol. |
| `TfNSW/TripDTO.swift` | `Decodable` structs mirroring the raw `trip` JSON. Nothing else. |
| `TfNSW/StopFinderDTO.swift` | `Decodable` structs mirroring the raw `stop_finder` JSON. |
| `TfNSW/Journey.swift` | Domain model (`Journey`, `Leg`, `LegStop`) plus mapping from DTO. |
| `TfNSW/TfNSWClient.swift` | URL building, auth header, `URLSession` calls, error typing. |
| `Storage/KeychainStore.swift` | Read/write/delete the API key in the Keychain. |
| `Storage/LocalStore.swift` | Recents, saved places, feedback. JSON file in Documents. |
| `Storage/Feedback.swift` | `PredictionFeedback` model + JSON export. |
| `Map/JourneyMapView.swift` | `Map` with per-leg polylines, stop markers, camera fitting. |
| `UI/GlassCard.swift` | Reusable glass surface + drag-to-expand bottom card. |
| `UI/HomeView.swift` | Map background + "Where to?" card + recents/saved. |
| `UI/SearchSheet.swift` | Debounced stop search, results list. |
| `UI/JourneyOptionsView.swift` | Ranked journey cards; selection drives the map. |
| `UI/LiveJourneyView.swift` | The main screen: legs, countdown, live badges, feedback. |
| `UI/LegRow.swift` | One leg row, including the ✓/✗ control. |
| `UI/SettingsView.swift` | API key entry, saved places, feedback export, developer menu. |
| `AppModel.swift` | Observable app state: client, store, current journey, navigation. |

**Modified:**
- `ios/project.yml` — add test target, add scheme with a test action.
- `ios/Sources/App/NextStopApp.swift:21-40` — `RootView` becomes the real app.
- `.github/workflows/ios-compile.yml` — run tests; screenshot the new screens.

**New tests, under `ios/Tests/`:**
- `TripDecodingTests.swift`, `TransitModeTests.swift`, `LocalStoreTests.swift`, `JourneyMappingTests.swift`
- `Fixtures/trip-sample.json`, `Fixtures/stopfinder-sample.json`

**Python:**
- Modify `collector/src/nextstop_collector/cli.py`, add `collector/tests/test_observe_cli.py`.

---

### Task 1: `nextstop observe` CLI command

Lets manually-noted board/arrive times be backfilled into the collector database without standing up the HTTP server. This is the only task with a fast local test loop, so it goes first.

**Files:**
- Modify: `collector/src/nextstop_collector/cli.py` (add a command after `shortcut_command`, around line 307)
- Test: `collector/tests/test_observe_cli.py` (create)

**Interfaces:**
- Consumes: `Observation` from `.storage.models`, `session_scope` from `.storage.db`, `now_utc`/`to_sydney` from `.timeutil`, `BY_KEY` from `.watchlist` (already imported in `cli.py`).
- Produces: CLI command `nextstop observe`. Nothing else depends on it.

- [ ] **Step 1: Write the failing test**

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

- [ ] **Step 2: Run the test and confirm it fails**

```bash
cd collector && uv run pytest tests/test_observe_cli.py -v
```

Expected: every test fails. The first two with exit code 2 and "No such command 'observe'".

- [ ] **Step 3: Implement the command**

In `collector/src/nextstop_collector/cli.py`, add after `shortcut_command`:

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

Add these imports at the top of `cli.py` if not already present:

```python
from datetime import datetime
from zoneinfo import ZoneInfo

from .storage.db import session_scope
from .storage.models import Observation
from .timeutil import now_utc, to_sydney
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
cd collector && uv run pytest tests/test_observe_cli.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Confirm the whole Python suite still passes**

```bash
cd collector && uv run pytest -q
```

Expected: no failures. If `test_observe_cli.py` interferes with another test's row counts, the fault is a shared `corridor` value — the fixtures above use `cli-` prefixes precisely to avoid that.

- [ ] **Step 6: Commit**

```bash
git add collector/src/nextstop_collector/cli.py collector/tests/test_observe_cli.py
git commit -m "Add nextstop observe for recording ground truth by hand"
```

---

### Task 2: Test target, real fixtures, and CI that runs tests

Without this there is no way to test any Swift on a Windows machine. Everything after this depends on it.

**Files:**
- Create: `ios/Tests/Fixtures/trip-sample.json`, `ios/Tests/Fixtures/stopfinder-sample.json`
- Create: `ios/Tests/FixtureLoader.swift`, `ios/Tests/FixtureLoaderTests.swift`
- Modify: `ios/project.yml` (add `NextStopTests` target and a `schemes:` block)
- Modify: `.github/workflows/ios-compile.yml` (add a test step after the build step)

**Interfaces:**
- Produces: `Fixture.data(_ name: String) -> Data` — every later test task loads JSON through this.

- [ ] **Step 1: Capture the two fixtures from the live API**

Run from the repo root. This uses the key already in `collector/.env` and never prints it. The departure time is pinned to a weekday morning so the response contains Metro, bus, and walk legs rather than the NightRide-only result a 2am call returns.

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

Expected: at least one journey containing a class 99 or 100 (walk) leg and a class 2 (Metro) or 5 (bus) leg. If every leg is class 5 and the time printed is not 08:00, the date has passed — bump the date in the snippet to the next Monday.

- [ ] **Step 2: Add the test target and scheme to `ios/project.yml`**

Append to the end of the file:

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

# Declared explicitly rather than left to XcodeGen's defaults: `xcodebuild test` only
# runs a test target that is attached to the scheme's test action, and an auto-created
# scheme does not attach one.
schemes:
  NextStop:
    build:
      targets:
        NextStop: all
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - NextStopTests
```

- [ ] **Step 3: Write the fixture loader and a test that proves the bundle carries the JSON**

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
    func testTripFixtureIsBundledAndParses() throws {
        let object = try JSONSerialization.jsonObject(with: Fixture.data("trip-sample")) as? [String: Any]
        let journeys = try XCTUnwrap(object?["journeys"] as? [[String: Any]])
        XCTAssertFalse(journeys.isEmpty)
    }

    func testStopFinderFixtureIsBundledAndParses() throws {
        let object = try JSONSerialization.jsonObject(with: Fixture.data("stopfinder-sample")) as? [String: Any]
        let locations = try XCTUnwrap(object?["locations"] as? [[String: Any]])
        XCTAssertFalse(locations.isEmpty)
    }
}
```

- [ ] **Step 4: Add the test step to CI**

In `.github/workflows/ios-compile.yml`, insert immediately after the `Build for simulator` step:

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

- [ ] **Step 5: Commit and push, then read the Actions result**

```bash
git add ios/project.yml ios/Tests .github/workflows/ios-compile.yml
git commit -m "Add an iOS unit test target with captured TfNSW fixtures"
git push
```

Expected: the workflow reaches "Run unit tests" and reports 2 tests passing. A failure at `xcodegen generate` means the YAML indentation of the appended block is wrong — `NextStopTests` must sit at the same indent as `NextStopWidget`, and `schemes:` at the same indent as `targets:`.

---

### Task 3: Transit modes and the colour system

**Files:**
- Create: `ios/Sources/App/Theme.swift`
- Create: `ios/Sources/App/TfNSW/TransitMode.swift`
- Test: `ios/Tests/TransitModeTests.swift`

**Interfaces:**
- Produces:
  - `enum TransitMode: Equatable` with cases `train, metro, lightRail, bus, coach, ferry, schoolBus, walk, cycle, unknown`
  - `init(productClass: Int?)`
  - `var displayName: String`, `var symbolName: String`, `var tint: Color`, `var isWalking: Bool`
  - `enum Theme` with `Theme.Colors.background`, `.surface`, `.textPrimary`, `.textSecondary`, `.onTime`, `.late`, `.noRealtime`, and `Theme.Spacing.{xs,s,m,l,xl}`, `Theme.Radius.{card,pill}`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/TransitModeTests.swift`:

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

    /// TfNSW uses both 99 and 100 for walking legs in the same response.
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

    func testEveryModeHasDistinctDisplayNameAndSymbol() {
        let all: [TransitMode] = [.train, .metro, .lightRail, .bus, .coach, .ferry, .schoolBus, .walk, .cycle, .unknown]
        XCTAssertEqual(Set(all.map(\.displayName)).count, all.count)
        for mode in all {
            XCTAssertFalse(mode.symbolName.isEmpty, "\(mode) has no symbol")
        }
    }
}
```

- [ ] **Step 2: Push and confirm the tests fail in CI**

```bash
git add ios/Tests/TransitModeTests.swift && git commit -m "Test mode mapping" && git push
```

Expected: compile failure, "cannot find 'TransitMode' in scope".

- [ ] **Step 3: Write `Theme.swift`**

```swift
import SwiftUI

enum Theme {
    enum Colors {
        static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
        static let surface = Color.white.opacity(0.08)
        static let stroke = Color.white.opacity(0.12)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)

        static let onTime = Color(red: 0.33, green: 0.66, blue: 0.41)
        static let late = Color(red: 0.87, green: 0.52, blue: 0.32)
        static let veryLate = Color(red: 0.77, green: 0.31, blue: 0.32)
        // Deliberately grey rather than a warning colour. Absent realtime is not a
        // problem with the service, it is a limit on what the app can honestly claim.
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
    /// Mode colours are published as hex by TfNSW. Storing them as hex rather than
    /// decimal components keeps them checkable against the brand guidance by eye.
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

- [ ] **Step 4: Write `TfNSW/TransitMode.swift`**

```swift
import SwiftUI

/// TfNSW product classes, per the Trip Planner v3.3 manual and confirmed against live
/// responses. Colours are the published TfNSW mode colours — using anything else costs
/// the instant recognition that makes a transit map readable at a glance.
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

    /// Published TfNSW mode colours. Train, Metro and Light Rail are confirmed against
    /// the official specifications (PMS 151C, PMS 321, and the L2 line colour). Bus,
    /// Ferry and Coach are the widely-published values but were not confirmed from a
    /// primary source — see Step 6.
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

- [ ] **Step 5: Push and confirm the tests pass**

```bash
git add ios/Sources/App/Theme.swift ios/Sources/App/TfNSW/TransitMode.swift
git commit -m "Add theme tokens and TfNSW mode mapping"
git push
```

Expected: 6 tests passing (2 from Task 2, 4 here).

- [ ] **Step 6: Confirm the three unverified mode colours**

Three of the six are already confirmed against primary sources and must not be changed:

| Mode | Hex | Source |
| --- | --- | --- |
| Train | `#F6891F` | CMYK 0/56/100/0, RGB 246/137/31, PMS 151C |
| Metro | `#168388` | CMYK 100/22/42/2, RGB 22/131/136, PMS 321 |
| Light Rail | `#DD1E25` | L2 Randwick line, CMYK 5/100/100/2 |

**Bus `#00B5EF`, Ferry `#5AB031`, and Coach `#732A82` are unconfirmed.** They are the commonly published values but no primary source was found for them. Check them against the *Transport Mode Symbols and Pictograms* dataset on data.nsw.gov.au, which ships the official artwork, and correct any that differ.

This is a real step, not a formality. Wrong mode colours are the single most visible way this app can look unofficial, and bus is the mode the user's own commute depends on most.

---

### Task 4: Decoding the raw `trip` response

**Files:**
- Create: `ios/Sources/App/TfNSW/TripDTO.swift`
- Test: `ios/Tests/TripDecodingTests.swift`

**Interfaces:**
- Consumes: `Fixture.data(_:)` from Task 2.
- Produces:
  - `struct TripDTO: Decodable { let journeys: [JourneyDTO]? }`
  - `struct JourneyDTO: Decodable { let legs: [LegDTO]? }`
  - `struct LegDTO: Decodable` with `duration: Int?`, `coords: [[Double]]?`, `origin: PlaceDTO?`, `destination: PlaceDTO?`, `transportation: TransportationDTO?`, `isRealtimeControlled: Bool?`, `stopSequence: [PlaceDTO]?`
  - `struct PlaceDTO: Decodable` with `id: String?`, `name: String?`, `disassembledName: String?`, `coord: [Double]?`, `departureTimePlanned: Date?`, `departureTimeEstimated: Date?`, `arrivalTimePlanned: Date?`, `arrivalTimeEstimated: Date?`
  - `struct TransportationDTO: Decodable` with `number: String?`, `disassembledName: String?`, `product: ProductDTO?`, `destination: NamedDTO?`
  - `struct ProductDTO: Decodable` with `productClass: Int?` (JSON key `class`), `name: String?`
  - `struct NamedDTO: Decodable { let name: String? }`
  - `static var tfnswDecoder: JSONDecoder` on `JSONDecoder`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/TripDecodingTests.swift`:

```swift
import XCTest
@testable import NextStop

final class TripDecodingTests: XCTestCase {
    private func decoded() throws -> TripDTO {
        try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
    }

    func testJourneysAndLegsDecode() throws {
        let trip = try decoded()
        let journeys = try XCTUnwrap(trip.journeys)
        XCTAssertFalse(journeys.isEmpty)
        let legs = try XCTUnwrap(journeys[0].legs)
        XCTAssertFalse(legs.isEmpty)
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

- [ ] **Step 2: Push and confirm the tests fail**

Expected: compile failure, "cannot find 'TripDTO' in scope".

- [ ] **Step 3: Write `TfNSW/TripDTO.swift`**

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
    /// Every field on these DTOs is optional on purpose. The Trip Planner omits keys
    /// rather than sending nulls, and it omits different ones depending on mode, time of
    /// day, and whether a service is realtime-tracked. One missing key must never cost
    /// the whole journey.
    static var tfnswDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 4: Push and confirm the tests pass**

```bash
git add ios/Sources/App/TfNSW/TripDTO.swift ios/Tests/TripDecodingTests.swift
git commit -m "Decode the TfNSW trip response against a captured fixture"
git push
```

Expected: 11 tests passing. If `testTimesDecodeAsDates` fails, the API returned a fractional-seconds timestamp — swap `.iso8601` for a custom `DateFormatter` with format `yyyy-MM-dd'T'HH:mm:ssZ` and locale `en_US_POSIX`.

---

### Task 5: The domain model

DTOs mirror the wire format; the UI should never see them. This task is the boundary.

**Files:**
- Create: `ios/Sources/App/TfNSW/Journey.swift`
- Test: `ios/Tests/JourneyMappingTests.swift`

**Interfaces:**
- Consumes: everything from Task 4, `TransitMode` from Task 3.
- Produces:
  - `struct Journey: Identifiable` — `id: Int`, `legs: [Leg]`, `departure: Date?`, `arrival: Date?`, `duration: TimeInterval?`, `transitLegs: [Leg]`
  - `struct Leg: Identifiable` — `id: UUID`, `mode`, `route: String?`, `headsign: String?`, `originName: String`, `destinationName: String`, `plannedDeparture/estimatedDeparture/plannedArrival/estimatedArrival: Date?`, `hasRealtime: Bool`, `path: [CLLocationCoordinate2D]`, `stops: [LegStop]`, `durationSeconds: Int?`
  - `var departure: Date?`, `var arrival: Date?`, `var delaySeconds: Int?` on `Leg`
  - `struct LegStop: Identifiable` — `id: String`, `name: String`, `coordinate: CLLocationCoordinate2D`, `departure: Date?`
  - `static func Journey.list(from: TripDTO) -> [Journey]`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/JourneyMappingTests.swift`:

```swift
import CoreLocation
import XCTest
@testable import NextStop

final class JourneyMappingTests: XCTestCase {
    private func journeys() throws -> [Journey] {
        let dto = try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
        return Journey.list(from: dto)
    }

    func testJourneysAreBuiltWithLegs() throws {
        let all = try journeys()
        XCTAssertFalse(all.isEmpty)
        XCTAssertFalse(all[0].legs.isEmpty)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "journey ids must be unique")
    }

    func testPathIsConvertedToCoordinates() throws {
        let transit = try XCTUnwrap(journeys().first?.transitLegs.first)
        XCTAssertGreaterThan(transit.path.count, 2)
        XCTAssertTrue((-45...(-25)).contains(transit.path[0].latitude))
    }

    func testDepartureFallsBackToPlannedWhenNoEstimate() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let leg = Leg(
            mode: .bus, route: "412", headsign: "USyd",
            originName: "A", destinationName: "B",
            plannedDeparture: planned, estimatedDeparture: nil,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: false, path: [], stops: [], durationSeconds: 600
        )
        XCTAssertEqual(leg.departure, planned)
        XCTAssertNil(leg.delaySeconds)
    }

    func testDelayIsTheDifferenceBetweenEstimateAndPlan() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let leg = Leg(
            mode: .bus, route: "412", headsign: "USyd",
            originName: "A", destinationName: "B",
            plannedDeparture: planned, estimatedDeparture: planned.addingTimeInterval(180),
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: 600
        )
        XCTAssertEqual(leg.delaySeconds, 180)
        XCTAssertEqual(leg.departure, planned.addingTimeInterval(180))
    }

    func testJourneySpansFirstDepartureToLastArrival() throws {
        let journey = try XCTUnwrap(journeys().first)
        XCTAssertNotNil(journey.departure)
        XCTAssertNotNil(journey.arrival)
        if let d = journey.departure, let a = journey.arrival {
            XCTAssertGreaterThan(a, d)
        }
    }

    func testWalkingLegsAreExcludedFromTransitLegs() throws {
        for journey in try journeys() {
            XCTAssertFalse(journey.transitLegs.contains { $0.mode.isWalking })
        }
    }
}
```

- [ ] **Step 2: Push and confirm the tests fail**

- [ ] **Step 3: Write `TfNSW/Journey.swift`**

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
    let id = UUID()
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
    let id: Int
    let legs: [Leg]

    var departure: Date? { legs.first?.departure }
    var arrival: Date? { legs.last?.arrival }
    var transitLegs: [Leg] { legs.filter { !$0.mode.isWalking } }

    var duration: TimeInterval? {
        guard let departure, let arrival else { return nil }
        return arrival.timeIntervalSince(departure)
    }

    static func list(from dto: TripDTO) -> [Journey] {
        (dto.journeys ?? []).enumerated().compactMap { index, journey in
            let legs = (journey.legs ?? []).map(Leg.init(dto:))
            return legs.isEmpty ? nil : Journey(id: index, legs: legs)
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
        self.init(
            mode: mode,
            route: transportation?.number ?? transportation?.disassembledName,
            headsign: transportation?.destination?.name,
            originName: dto.origin?.disassembledName ?? dto.origin?.name ?? "",
            destinationName: dto.destination?.disassembledName ?? dto.destination?.name ?? "",
            plannedDeparture: dto.origin?.departureTimePlanned,
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

- [ ] **Step 4: Push and confirm the tests pass**

```bash
git add ios/Sources/App/TfNSW/Journey.swift ios/Tests/JourneyMappingTests.swift
git commit -m "Map trip DTOs onto a journey domain model"
git push
```

Expected: 17 tests passing.

---

### Task 6: Keychain storage for the API key

**Files:**
- Create: `ios/Sources/App/Storage/KeychainStore.swift`
- Test: `ios/Tests/KeychainStoreTests.swift`

**Interfaces:**
- Produces: `enum KeychainStore` with `static func save(_ key: String) throws`, `static func read() -> String?`, `static func delete()`, and `struct KeychainError: Error { let status: OSStatus }`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/KeychainStoreTests.swift`:

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

    func testReadReturnsNilWhenNothingStored() {
        XCTAssertNil(KeychainStore.read())
    }

    func testSavedKeyReadsBack() throws {
        try KeychainStore.save("abc123")
        XCTAssertEqual(KeychainStore.read(), "abc123")
    }

    /// Saving twice must overwrite rather than fail with errSecDuplicateItem, which is
    /// what a plain SecItemAdd does.
    func testSavingTwiceOverwrites() throws {
        try KeychainStore.save("first")
        try KeychainStore.save("second")
        XCTAssertEqual(KeychainStore.read(), "second")
    }

    func testDeleteRemovesTheKey() throws {
        try KeychainStore.save("abc123")
        KeychainStore.delete()
        XCTAssertNil(KeychainStore.read())
    }
}
```

- [ ] **Step 2: Push and confirm the tests fail**

- [ ] **Step 3: Write `Storage/KeychainStore.swift`**

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
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        // Without a device passcode the default accessibility class silently fails to
        // store, so this is the one that works on every device the app can run on.
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

- [ ] **Step 4: Push and confirm the tests pass**

```bash
git add ios/Sources/App/Storage/KeychainStore.swift ios/Tests/KeychainStoreTests.swift
git commit -m "Store the TfNSW key in the Keychain"
git push
```

Expected: 21 tests passing.

If every Keychain test fails with `OSStatus -34018` (`errSecMissingEntitlement`), the tests are running without a host application, so there is no keychain access group. Fix it by giving the test target a host — in `ios/project.yml`, under `NextStopTests`, replace the `dependencies:` block with:

```yaml
    dependencies:
      - target: NextStop
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/NextStop.app/NextStop"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

---

### Task 7: The API client

**Files:**
- Create: `ios/Sources/App/TfNSW/TfNSWClient.swift`
- Test: `ios/Tests/TfNSWClientTests.swift`

**Interfaces:**
- Consumes: `KeychainStore` (Task 6), `TripDTO` (Task 4), `Journey` (Task 5).
- Produces:
  - `protocol HTTPFetching { func data(for request: URLRequest) async throws -> (Data, URLResponse) }` with `URLSession: HTTPFetching`
  - `struct TfNSWClient { init(session: HTTPFetching = URLSession.shared, keyProvider: @escaping () -> String? = KeychainStore.read) }`
  - `func journeys(originID: String, destinationID: String, departing: Date) async throws -> [Journey]`
  - `func findStops(matching query: String) async throws -> [StopSuggestion]`
  - `enum TfNSWError: Error, Equatable { case missingKey, unauthorised, http(Int), transport }`
  - `struct StopSuggestion: Identifiable, Codable, Hashable { let id: String; let name: String; let isBest: Bool }`
  - `func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest` (internal, so tests can assert on it)

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/TfNSWClientTests.swift`:

```swift
import XCTest
@testable import NextStop

private struct StubFetcher: HTTPFetching {
    var status: Int = 200
    var payload: Data = Data()
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
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
        XCTAssertTrue(url.contains("outputFormat=rapidJSON"))
        XCTAssertTrue(url.contains("coordOutputFormat=EPSG:4326") || url.contains("coordOutputFormat=EPSG%3A4326"))
        XCTAssertTrue(url.hasPrefix("https://api.transport.nsw.gov.au/v1/tp/trip"))
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

- [ ] **Step 2: Push and confirm the tests fail**

- [ ] **Step 3: Write `TfNSW/StopFinderDTO.swift`**

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

- [ ] **Step 4: Write `TfNSW/TfNSWClient.swift`**

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
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {}

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

    func journeys(originID: String, destinationID: String, departing: Date) async throws -> [Journey] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: departing)

        let request = try makeRequest(path: "trip", query: [
            URLQueryItem(name: "depArrMacro", value: "dep"),
            URLQueryItem(name: "itdDate", value: String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)),
            URLQueryItem(name: "itdTime", value: String(format: "%02d%02d", parts.hour!, parts.minute!)),
            URLQueryItem(name: "type_origin", value: "any"),
            URLQueryItem(name: "name_origin", value: originID),
            URLQueryItem(name: "type_destination", value: "any"),
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
            .compactMap { location in
                guard let id = location.id,
                      let name = location.disassembledName ?? location.name else { return nil }
                return (StopSuggestion(id: id, name: name, isBest: location.isBest ?? false), location.matchQuality ?? 0)
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
            (data, response) = try await session.data(for: request)
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

- [ ] **Step 5: Push and confirm the tests pass**

```bash
git add ios/Sources/App/TfNSW/TfNSWClient.swift ios/Sources/App/TfNSW/StopFinderDTO.swift ios/Tests/TfNSWClientTests.swift
git commit -m "Add the TfNSW API client"
git push
```

Expected: 26 tests passing.

---

### Task 8: Local storage for recents, saved places, and feedback

A JSON file, not SwiftData. Fifty rows of personal data do not need a schema, a migration story, or a model container.

**Files:**
- Create: `ios/Sources/App/Storage/Feedback.swift`
- Create: `ios/Sources/App/Storage/LocalStore.swift`
- Test: `ios/Tests/LocalStoreTests.swift`

**Interfaces:**
- Consumes: `StopSuggestion` (Task 7), `Leg` (Task 5).
- Produces:
  - `struct PredictionFeedback: Codable, Identifiable` — `id: UUID`, `recordedAt: Date`, `wasCorrect: Bool`, `mode: String`, `route: String?`, `originName: String`, `destinationName: String`, `plannedDeparture: Date?`, `estimatedDeparture: Date?`, `hadRealtime: Bool`, `errorSeconds: Int?`
  - `init(leg: Leg, wasCorrect: Bool, tappedAt: Date)`
  - `final class LocalStore: ObservableObject` — `init(fileURL: URL)`, `static let shared`, `@Published private(set) var recents: [StopSuggestion]`, `@Published private(set) var saved: [StopSuggestion]`, `@Published private(set) var feedback: [PredictionFeedback]`
  - `func addRecent(_:)`, `func toggleSaved(_:)`, `func isSaved(_:) -> Bool`, `func record(_ feedback: PredictionFeedback)`, `func exportFeedbackJSON() throws -> Data`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/LocalStoreTests.swift`:

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

    func testStartsEmpty() {
        let store = LocalStore(fileURL: url)
        XCTAssertTrue(store.recents.isEmpty)
        XCTAssertTrue(store.saved.isEmpty)
        XCTAssertTrue(store.feedback.isEmpty)
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

    /// A tap is worth more than a verdict: the gap between the predicted departure and
    /// the moment the user tapped is the measurable error.
    func testFeedbackFromALegComputesErrorAgainstTheTapTime() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let leg = Leg(
            mode: .bus, route: "412", headsign: "USyd",
            originName: "Railway Square", destinationName: "USyd",
            plannedDeparture: planned, estimatedDeparture: planned.addingTimeInterval(60),
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: 600
        )
        let feedback = PredictionFeedback(
            leg: leg, wasCorrect: true, tappedAt: planned.addingTimeInterval(150)
        )
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
        let data = try store.exportFeedbackJSON()
        let decoded = try JSONDecoder.tfnswDecoder.decode([PredictionFeedback].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].mode, "Metro")
    }
}
```

- [ ] **Step 2: Push and confirm the tests fail**

- [ ] **Step 3: Write `Storage/Feedback.swift`**

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

- [ ] **Step 4: Write `Storage/LocalStore.swift`**

```swift
import Foundation

/// One JSON file in Documents. Not SwiftData: this holds tens of rows of personal data
/// with no relationships and no queries, and a model container would be more moving parts
/// than the whole feature.
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
        // A corrupt or absent file starts empty rather than throwing. Losing a recents
        // list is not worth refusing to launch over.
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

- [ ] **Step 5: Push and confirm the tests pass**

```bash
git add ios/Sources/App/Storage/Feedback.swift ios/Sources/App/Storage/LocalStore.swift ios/Tests/LocalStoreTests.swift
git commit -m "Persist recents, saved places, and prediction feedback"
git push
```

Expected: 34 tests passing. `.iso8601` must be set on both encode and decode or `testEverythingSurvivesAReload` fails on the date.

---

### Task 9: The journey map

**Files:**
- Create: `ios/Sources/App/Map/JourneyMapView.swift`
- Test: `ios/Tests/MapRegionTests.swift`

**Interfaces:**
- Consumes: `Journey`, `Leg`, `TransitMode`.
- Produces:
  - `struct JourneyMapView: View { init(journey: Journey?, showsUserLocation: Bool = true) }`
  - `enum MapFraming { static func region(for journey: Journey, padding: Double = 1.4) -> MKCoordinateRegion? }`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/MapRegionTests.swift`:

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
        let leg = Leg(
            mode: .walk, route: nil, headsign: nil, originName: "A", destinationName: "B",
            plannedDeparture: nil, estimatedDeparture: nil, plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: false, path: [point, point], stops: [], durationSeconds: 60
        )
        let region = MapFraming.region(for: Journey(id: 0, legs: [leg]))
        XCTAssertNotNil(region)
        XCTAssertGreaterThanOrEqual(region!.span.latitudeDelta, 0.005)
    }

    func testJourneyWithNoGeometryHasNoRegion() {
        let leg = Leg(
            mode: .walk, route: nil, headsign: nil, originName: "A", destinationName: "B",
            plannedDeparture: nil, estimatedDeparture: nil, plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: false, path: [], stops: [], durationSeconds: 60
        )
        XCTAssertNil(MapFraming.region(for: Journey(id: 0, legs: [leg])))
    }
}
```

- [ ] **Step 2: Push and confirm the tests fail**

- [ ] **Step 3: Write `Map/JourneyMapView.swift`**

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
    var showsUserLocation: Bool = true

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            if showsUserLocation {
                UserAnnotation()
            }
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
                        Annotation(leg.originName, coordinate: start) {
                            interchangeDot(leg.mode)
                        }
                    }
                }
                if let last = journey.legs.last?.path.last {
                    Annotation(journey.legs.last?.destinationName ?? "", coordinate: last) {
                        interchangeDot(journey.legs.last?.mode ?? .unknown)
                    }
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
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .region(region)
        }
    }
}
```

- [ ] **Step 4: Push and confirm the tests pass**

```bash
git add ios/Sources/App/Map/JourneyMapView.swift ios/Tests/MapRegionTests.swift
git commit -m "Draw journey routes on the map with per-mode colours"
git push
```

Expected: 37 tests passing.

---

### Task 10: App model and navigation state

**Files:**
- Create: `ios/Sources/App/AppModel.swift`
- Test: `ios/Tests/AppModelTests.swift`

**Interfaces:**
- Consumes: `TfNSWClient`, `LocalStore`, `Journey`, `StopSuggestion`.
- Produces:
  - `@MainActor final class AppModel: ObservableObject`
  - `init(client: TfNSWClient = TfNSWClient(), store: LocalStore = .shared)`
  - `@Published var destination: StopSuggestion?`, `@Published var journeys: [Journey]`, `@Published var selectedJourneyID: Int?`, `@Published var phase: Phase`, `@Published var searchResults: [StopSuggestion]`
  - `enum Phase: Equatable { case idle, searching, planning, ready, failed(TfNSWError) }`
  - `var selectedJourney: Journey?`
  - `func search(_ text: String) async`, `func plan(to: StopSuggestion, from originID: String) async`, `func refresh() async`, `func reset()`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/AppModelTests.swift`:

```swift
import XCTest
@testable import NextStop

private struct StubFetcher: HTTPFetching {
    var status: Int = 200
    var payload: Data = Data()
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (payload, response)
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    private func store() -> LocalStore {
        LocalStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("model-\(UUID().uuidString).json"))
    }

    private func model(status: Int = 200, payload: Data = Data()) -> AppModel {
        AppModel(
            client: TfNSWClient(session: StubFetcher(status: status, payload: payload), keyProvider: { "k" }),
            store: store()
        )
    }

    func testPlanningPopulatesJourneysAndSelectsTheFirst() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: StopSuggestion(id: "2", name: "USyd", isBest: true), from: "1")
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.journeys.isEmpty)
        XCTAssertEqual(model.selectedJourneyID, model.journeys.first?.id)
        XCTAssertNotNil(model.selectedJourney)
    }

    func testPlanningRecordsTheDestinationAsRecent() async {
        let model = model(payload: Fixture.data("trip-sample"))
        let destination = StopSuggestion(id: "2", name: "USyd", isBest: true)
        await model.plan(to: destination, from: "1")
        XCTAssertEqual(model.store.recents.first?.id, "2")
    }

    func testAnUnauthorisedPlanSurfacesTheError() async {
        let model = model(status: 401)
        await model.plan(to: StopSuggestion(id: "2", name: "USyd", isBest: true), from: "1")
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

    func testResetClearsEverything() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: StopSuggestion(id: "2", name: "USyd", isBest: true), from: "1")
        model.reset()
        XCTAssertTrue(model.journeys.isEmpty)
        XCTAssertNil(model.destination)
        XCTAssertEqual(model.phase, .idle)
    }
}
```

- [ ] **Step 2: Push and confirm the tests fail**

- [ ] **Step 3: Write `AppModel.swift`**

```swift
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle, searching, planning, ready
        case failed(TfNSWError)
    }

    /// Below this the Stop Finder returns most of Sydney and the list is useless.
    private static let minimumQueryLength = 3

    let store: LocalStore
    private let client: TfNSWClient

    @Published var destination: StopSuggestion?
    @Published var journeys: [Journey] = []
    @Published var selectedJourneyID: Int?
    @Published var searchResults: [StopSuggestion] = []
    @Published var phase: Phase = .idle

    private var originID: String?

    init(client: TfNSWClient = TfNSWClient(), store: LocalStore = .shared) {
        self.client = client
        self.store = store
    }

    var selectedJourney: Journey? {
        journeys.first { $0.id == selectedJourneyID }
    }

    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minimumQueryLength else {
            searchResults = []
            return
        }
        phase = .searching
        do {
            searchResults = try await client.findStops(matching: query)
            phase = .idle
        } catch let error as TfNSWError {
            searchResults = []
            phase = .failed(error)
        } catch {
            searchResults = []
            phase = .failed(.transport)
        }
    }

    func plan(to stop: StopSuggestion, from originID: String) async {
        destination = stop
        self.originID = originID
        phase = .planning
        do {
            let found = try await client.journeys(
                originID: originID, destinationID: stop.id, departing: Date()
            )
            journeys = found
            selectedJourneyID = found.first?.id
            store.addRecent(stop)
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

    /// Re-plans in place, keeping the user's selected option if it still exists. Called on
    /// a timer while the journey screen is open.
    func refresh() async {
        guard let destination, let originID else { return }
        let previous = selectedJourneyID
        await plan(to: destination, from: originID)
        if let previous, journeys.contains(where: { $0.id == previous }) {
            selectedJourneyID = previous
        }
    }

    func reset() {
        destination = nil
        journeys = []
        selectedJourneyID = nil
        searchResults = []
        originID = nil
        phase = .idle
    }
}
```

- [ ] **Step 4: Push and confirm the tests pass**

```bash
git add ios/Sources/App/AppModel.swift ios/Tests/AppModelTests.swift
git commit -m "Add the app model driving search, planning, and refresh"
git push
```

Expected: 43 tests passing.

---

### Task 11: Glass surfaces and the leg row

The two reusable pieces of UI, built before the screens that compose them.

**Files:**
- Create: `ios/Sources/App/UI/GlassCard.swift`
- Create: `ios/Sources/App/UI/LegRow.swift`

**Interfaces:**
- Produces:
  - `struct GlassCard<Content: View>: View { init(@ViewBuilder content: () -> Content) }`
  - `extension View { func glassSurface(cornerRadius: CGFloat) -> some View }`
  - `struct LegRow: View { init(leg: Leg, isNext: Bool, now: Date, onFeedback: ((Bool) -> Void)?) }`
  - `enum DepartureStatus { case onTime, late(Int), early(Int), scheduledOnly; init(leg: Leg); var label: String; var tint: Color }`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/DepartureStatusTests.swift`:

```swift
import XCTest
@testable import NextStop

final class DepartureStatusTests: XCTestCase {
    private func leg(planned: Date?, estimated: Date?, realtime: Bool) -> Leg {
        Leg(
            mode: .bus, route: "412", headsign: "USyd",
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

    func testWithinAMinuteCountsAsOnTime() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(30), realtime: true))
        XCTAssertEqual(status, .onTime)
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

- [ ] **Step 2: Push and confirm the tests fail**

- [ ] **Step 3: Write `UI/GlassCard.swift`**

```swift
import SwiftUI

extension View {
    /// iOS 26's Liquid Glass where available, with the material fallback kept because the
    /// simulator screenshots in CI have rendered glass inconsistently.
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

- [ ] **Step 4: Write `UI/LegRow.swift`**

```swift
import SwiftUI

enum DepartureStatus: Equatable {
    case onTime
    case late(Int)
    case early(Int)
    case scheduledOnly

    /// A minute of slack either way. TfNSW estimates jitter by seconds constantly and
    /// showing "1 min late" that flips back a moment later reads as a broken app.
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

                Text(leg.mode.isWalking ? "to \(leg.destinationName)" : "from \(leg.originName)")
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if !leg.mode.isWalking {
                    Text(status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.tint)
                }

                if hasDeparted, let onFeedback, !leg.mode.isWalking {
                    HStack(spacing: Theme.Spacing.s) {
                        Text("Was this right?")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Button { onFeedback(true) } label: {
                            Label("Yes", systemImage: "checkmark")
                        }
                        Button { onFeedback(false) } label: {
                            Label("No", systemImage: "xmark")
                        }
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

- [ ] **Step 5: Push and confirm the tests pass**

```bash
git add ios/Sources/App/UI/GlassCard.swift ios/Sources/App/UI/LegRow.swift ios/Tests/DepartureStatusTests.swift
git commit -m "Add glass surfaces and the leg row with an honest realtime badge"
git push
```

Expected: 47 tests passing.

---

### Task 12: Home, search, and journey options screens

**Files:**
- Create: `ios/Sources/App/UI/HomeView.swift`
- Create: `ios/Sources/App/UI/SearchSheet.swift`
- Create: `ios/Sources/App/UI/JourneyOptionsView.swift`

**Interfaces:**
- Consumes: `AppModel`, `LocalStore`, `JourneyMapView`, `GlassCard`, `Theme`, `TransitMode`.
- Produces: `struct HomeView: View`, `struct SearchSheet: View`, `struct JourneyOptionsView: View`. All read `AppModel` from the environment.

- [ ] **Step 1: Write `UI/SearchSheet.swift`**

```swift
import SwiftUI

struct SearchSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if !model.store.saved.isEmpty && text.isEmpty {
                    Section("Saved") { rows(model.store.saved) }
                }
                if !model.store.recents.isEmpty && text.isEmpty {
                    Section("Recent") { rows(model.store.recents) }
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rows(_ stops: [StopSuggestion]) -> some View {
        ForEach(stops) { stop in
            Button {
                select(stop)
            } label: {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(stop.name)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if model.store.isSaved(stop) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
            }
            .swipeActions(edge: .leading) {
                Button(model.store.isSaved(stop) ? "Unsave" : "Save") {
                    model.store.toggleSaved(stop)
                }
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

    private func select(_ stop: StopSuggestion) {
        dismiss()
        Task { await model.plan(to: stop, from: "current-location-placeholder") }
    }
}
```

- [ ] **Step 2: Write `UI/JourneyOptionsView.swift`**

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

- [ ] **Step 3: Write `UI/HomeView.swift`**

```swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSearch = false
    @State private var showingSettings = false

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
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Theme.Colors.textSecondary)
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
        .sheet(isPresented: $showingSearch) { SearchSheet().environmentObject(model) }
        .sheet(isPresented: $showingSettings) { SettingsView().environmentObject(model) }
    }

    @ViewBuilder
    private func errorRow(_ error: TfNSWError) -> some View {
        let message: String = switch error {
        case .missingKey: "Add your TfNSW API key in Settings"
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

- [ ] **Step 4: Commit, but do not push**

**Tasks 12, 13, and 14 are one compile unit.** `HomeView` navigates to `LiveJourneyView` and `SettingsView`, which do not exist until Tasks 13 and 14. Pushing now would spend a five-minute CI round trip to be told exactly that.

These three tasks add no tests. They are view bodies, and a snapshot test of CI-rendered glass costs more to maintain than it catches. The gate for all three is the compile and the screenshots at the end of Task 14.

```bash
git add ios/Sources/App/UI/HomeView.swift ios/Sources/App/UI/SearchSheet.swift ios/Sources/App/UI/JourneyOptionsView.swift
git commit -m "Add the home, search, and journey option screens"
```

Expected: a local commit. Nothing runs.

---

### Task 13: The live journey screen

**Files:**
- Create: `ios/Sources/App/UI/LiveJourneyView.swift`

**Interfaces:**
- Consumes: `AppModel`, `LegRow`, `JourneyMapView`, `PredictionFeedback`, `LocalStore`.
- Produces: `struct LiveJourneyView: View`.

- [ ] **Step 1: Write `UI/LiveJourneyView.swift`**

```swift
import SwiftUI

struct LiveJourneyView: View {
    @EnvironmentObject private var model: AppModel

    @State private var now = Date()
    @State private var recorded: Set<UUID> = []

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// The realtime feed itself only moves every 10–15 seconds, so anything faster than
    /// this spends quota to redraw the same numbers.
    private let refreshEvery: TimeInterval = 30
    @State private var lastRefresh = Date()

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
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
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
                Text("\(Int(duration / 60)) min · \(journey.transitLegs.count) service\(journey.transitLegs.count == 1 ? "" : "s")")
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
        model.store.record(PredictionFeedback(leg: leg, wasCorrect: wasCorrect, tappedAt: Date()))
        withAnimation(.snappy) { _ = recorded.insert(leg.id) }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add ios/Sources/App/UI/LiveJourneyView.swift
git commit -m "Add the live journey screen with per-leg feedback"
```

Do not push yet — the build still lacks `SettingsView`. Task 14 completes the set.

---

### Task 14: Settings, root wiring, and CI screenshots

The task that makes the app launchable and visible.

**Files:**
- Create: `ios/Sources/App/UI/SettingsView.swift`
- Modify: `ios/Sources/App/NextStopApp.swift:21-40`
- Modify: `.github/workflows/ios-compile.yml:73-88`

**Interfaces:**
- Consumes: everything above.
- Produces: `struct SettingsView: View`, a rewritten `RootView`.

- [ ] **Step 1: Write `UI/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var saved = false
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
                        saved = true
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if saved || KeychainStore.read() != nil {
                        Label("A key is stored on this device", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.Colors.onTime)
                    }
                } header: {
                    Text("Transport NSW API key")
                } footer: {
                    Text("Free from opendata.transport.nsw.gov.au. Stored in the iOS Keychain and sent only to Transport NSW.")
                }

                Section("Feedback") {
                    LabeledContent("Recorded", value: "\(model.store.feedback.count)")
                    if let exported {
                        ShareLink("Export as JSON", item: exported)
                    }
                }
                .onAppear(perform: writeExport)

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
        }
        .preferredColorScheme(.dark)
    }

    /// ShareLink needs a file that already exists, so the export is written when the
    /// screen appears rather than when the user taps.
    private func writeExport() {
        guard !model.store.feedback.isEmpty,
              let data = try? model.store.exportFeedbackJSON() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nextstop-feedback.json")
        try? data.write(to: url, options: .atomic)
        exported = url
    }
}
```

- [ ] **Step 2: Rewrite `RootView` in `ios/Sources/App/NextStopApp.swift`**

Replace lines 21–40 with:

```swift
struct RootView: View {
    @StateObject private var model = AppModel()

    // CI launches the simulator with `-initialScreen settings` to screenshot a screen it
    // cannot otherwise reach. Without a provisioned device this is the only way to look at
    // these layouts at all. UserDefaults picks launch arguments up via NSArgumentDomain.
    @State private var initialScreen = UserDefaults.standard.string(forKey: "initialScreen")

    var body: some View {
        NavigationStack {
            HomeView()
                .background(Theme.Colors.background)
        }
        .environmentObject(model)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.textPrimary)
        .sheet(isPresented: .constant(initialScreen == "settings")) {
            SettingsView().environmentObject(model)
        }
    }
}
```

Leave the `@main struct NextStopApp` above it untouched — `SpikeSession` is still injected for the developer screens.

- [ ] **Step 3: Update the CI screenshot step**

In `.github/workflows/ios-compile.yml`, replace the `for tab in spike layouts log` loop with:

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

- [ ] **Step 4: Push and confirm the whole thing builds, tests, and screenshots**

```bash
git add ios/Sources/App/UI/SettingsView.swift ios/Sources/App/NextStopApp.swift .github/workflows/ios-compile.yml
git commit -m "Wire the journey app as the root screen"
git push
```

Expected: build succeeds, 47 tests pass, and the `simulator-screenshots` artifact contains `home.png` showing a dark map with a glass "Where to?" card, and `settings.png` showing the key field.

- [ ] **Step 5: Download the artifact and look at both screenshots**

This is the only visual check that exists. A screenshot showing a white background means `preferredColorScheme` is not reaching the sheet; a screenshot showing a blank grey rectangle where the map should be is expected in the simulator without a location fix and is not a failure.

---

### Task 15: Origin from current location

Every earlier task passes the literal string `"current-location-placeholder"` as the origin. This task makes it real, and is deliberately last so that nothing before it is blocked on location permission behaviour.

**Files:**
- Create: `ios/Sources/App/LocationProvider.swift`
- Modify: `ios/Sources/App/UI/SearchSheet.swift` (the `select(_:)` method)
- Modify: `ios/Sources/App/AppModel.swift` (add `originDescription`)
- Test: `ios/Tests/LocationProviderTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor final class LocationProvider: NSObject, ObservableObject` with `@Published private(set) var coordinate: CLLocationCoordinate2D?`, `func requestWhenInUse()`, `func start()`, `func stop()`
  - `static func tfnswOriginString(for coordinate: CLLocationCoordinate2D) -> String`

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/LocationProviderTests.swift`:

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

- [ ] **Step 2: Push and confirm the test fails**

- [ ] **Step 3: Write `LocationProvider.swift`**

```swift
import CoreLocation

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var authorisation: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        authorisation = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    func start() { manager.startUpdatingLocation() }
    func stop() { manager.stopUpdatingLocation() }

    /// EFA wants longitude before latitude here, unlike the `coords` arrays it returns.
    /// Six decimal places is roughly 0.1 m — more than enough and shorter than the default
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
                manager.startUpdatingLocation()
            }
        }
    }
}
```

- [ ] **Step 4: Use it as the origin**

In `AppModel.swift`, add a stored property and an accessor:

```swift
    let location = LocationProvider()

    /// Falls back to Chatswood rather than refusing to plan. A journey from the wrong
    /// origin is still visible and correctable; a blank screen tells the user nothing.
    var originString: String {
        if let coordinate = location.coordinate {
            return LocationProvider.tfnswOriginString(for: coordinate)
        }
        return "10101100"
    }
```

In `SearchSheet.swift`, change `select(_:)` to:

```swift
    private func select(_ stop: StopSuggestion) {
        dismiss()
        Task { await model.plan(to: stop, from: model.originString) }
    }
```

In `HomeView.swift`, request permission when the map first appears — add to the `ZStack`:

```swift
        .onAppear {
            model.location.requestWhenInUse()
            model.location.start()
        }
        .onDisappear { model.location.stop() }
```

- [ ] **Step 5: Push and confirm everything passes**

```bash
git add ios/Sources/App/LocationProvider.swift ios/Sources/App/AppModel.swift ios/Sources/App/UI/SearchSheet.swift ios/Sources/App/UI/HomeView.swift ios/Tests/LocationProviderTests.swift
git commit -m "Plan journeys from the current location"
git push
```

Expected: 48 tests passing.

- [ ] **Step 6: Install on the phone and use it**

Push to `main`, let Codemagic build, install from TestFlight. Then the real gate: **plan a journey to somewhere you have not been, follow it, and tap ✓ or ✗ on each leg.** Export the feedback from Settings afterwards.

The fallback origin ID `10101100` in Step 4 is Chatswood's Trip Planner ID and is a guess — confirm it with `uv run python -c "from nextstop_collector.tfnsw.client import TfnswClient; from nextstop_collector.tfnsw.stops import find_candidates; c=TfnswClient(); print(find_candidates(c,'Chatswood Station',limit=1))"` and correct it if it differs.

---

## Deliberately Not In This Plan

Recorded so they are visible decisions rather than omissions:

- **Live Activity for real journeys.** The spike works on device; wiring it to `Journey` is a follow-up once there is a fortnight of using the app to say what belongs on a Lock Screen.
- **The VPS proxy.** Needed the day a second person installs this, because nobody else will type in an API key. `deploy/nextstop-api.service` already exists for it.
- **Porting the collector's quirk filters to Swift.** They operate on raw GTFS-Realtime feeds; the Trip Planner endpoint this app uses returns estimated times directly.
- **Trip Planner rate limiting in the app.** The collector needs a token bucket because it runs unattended. One person tapping a phone cannot approach 60,000 calls a day.
- **Offline caching.** Every screen needs live data to be worth anything.
- **Snapshot tests of the UI.** The CI screenshots are the check.
