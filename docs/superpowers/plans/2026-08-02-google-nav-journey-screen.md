# Google-Style Journey Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework `LiveJourneyView` to Google Maps' navigation layout: street-level follow camera, floating compact banner with a "Then" chip, a compact Google bottom bar with overview + Exit, and working swipe-back with the back chevron deleted.

**Architecture:** Restyle in place — the banner state derivation (`JourneyActivityState`), sheet physics (`SheetPhysics`), and camera reducer (`CameraMode`) are all kept untouched. Only chrome, defaults, and one new UIKit shim change. Spec: `docs/superpowers/specs/2026-08-01-google-nav-journey-screen-design.md`.

**Tech Stack:** SwiftUI + MapKit (iOS 26 target, Swift 5 language mode), XCTest, XcodeGen, GitHub Actions CI.

## Global Constraints

- **No local build or test runs.** The dev machine is Windows; the only verification is pushing and watching GitHub Actions (`.github/workflows/ios-compile.yml`: build → unit tests → screenshots). Steps that say "verify" mean "verify at the next push checkpoint" — Tasks 4 and 8 are the only pushes.
- Watch CI with `gh run watch <run-id> --exit-status` (run id from `gh run list --branch round-4-google-nav-screen --limit 1 --json databaseId --jq '.[0].databaseId'`). **Never** use `gh pr checks --watch` — it exits prematurely.
- Branch: `round-4-google-nav-screen` (exists; spec already committed on it). PR targets `main`.
- Swift 5 language mode (`SWIFT_VERSION: "5.0"` in `ios/project.yml`) — no `@retroactive`, no strict-concurrency annotations.
- New source files need no project registration — XcodeGen globs `ios/Sources/App` and `ios/Sources/Shared` at CI time.
- Design tokens only: every colour, spacing, and radius comes from `Theme`; compose tokens (`Theme.Spacing.s + Theme.Spacing.xs`) rather than hardcoding.
- Comments explain *why*, sparingly, matching this codebase's voice; no what-comments, no section dividers.
- Standing traps: never construct a `@MainActor` type in a default argument; Swift forbids static stored properties on generic types; never remove `-fakeHeading 45 -legacyGlass YES`, the location grants, or the post-install re-grant from the workflow. Repo is public — no personal data in code or docs.
- Commit messages match the repo's voice: short imperative sentences ("Trade the heading beam for Google's arrow"), no conventional-commit prefixes.

---

### Task 1: Time remaining for the bottom bar

**Files:**
- Modify: `ios/Sources/App/UI/TimeDisplay.swift`
- Test: `ios/Tests/TimeDisplayTests.swift`

**Interfaces:**
- Consumes: existing `TimeDisplay.longDurationLabel(seconds:)`.
- Produces: `static func remainingLabel(until arrival: Date?, now: Date) -> String?` — "43 min" / "1 hr 15 min" while ahead, `"Arrived"` at or past arrival, `nil` when `arrival` is nil. Task 5 renders it as the bar's big number.

- [ ] **Step 1: Write the failing tests**

Append to `ios/Tests/TimeDisplayTests.swift` (existing `anchor` property is in scope):

```swift
    func testRemainingLabelCountsDownToArrival() {
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(43 * 60), now: anchor), "43 min")
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(75 * 60), now: anchor), "1 hr 15 min")
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(20), now: anchor), "1 min")
    }

    func testRemainingLabelReadsArrivedOncePassed() {
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor, now: anchor), "Arrived")
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(-300), now: anchor), "Arrived")
    }

    func testRemainingLabelHidesWithoutAnArrival() {
        XCTAssertNil(TimeDisplay.remainingLabel(until: nil, now: anchor))
    }
```

- [ ] **Step 2: Implement**

Append inside `enum TimeDisplay` in `ios/Sources/App/UI/TimeDisplay.swift`:

```swift
    /// The journey bar's big number: time left until arrival. Past arrival it reads
    /// "Arrived" rather than counting negative or vanishing under the Exit button.
    static func remainingLabel(until arrival: Date?, now: Date) -> String? {
        guard let arrival else { return nil }
        let seconds = Int(arrival.timeIntervalSince(now))
        guard seconds > 0 else { return "Arrived" }
        return longDurationLabel(seconds: seconds)
    }
```

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/UI/TimeDisplay.swift ios/Tests/TimeDisplayTests.swift
git commit -m "Count down to arrival for the journey bar"
```

---

### Task 2: The Then chip's model line

**Files:**
- Modify: `ios/Sources/App/UI/JourneyBanner.swift` (model only — `JourneyBannerModel`)
- Modify: `docs/superpowers/specs/2026-08-01-google-nav-journey-screen-design.md` (one sentence)
- Test: `ios/Tests/JourneyBannerModelTests.swift`

**Interfaces:**
- Consumes: `JourneyActivityAttributes.ContentState.nextLegLine` ("Then T1 · 8:12 am", populated for walking and waiting phases).
- Produces: `JourneyBannerModel.thenLine: String?` — non-nil **only while walking**. Task 3 renders it as the chip.

Walking-only, not walking-and-waiting as the spec first said: during waiting, `nextLegLine` names the same service as the "Board T1…" title, so a chip would duplicate the banner. The Live Activity already gates its next-leg line to the walking phase for exactly this reason (`JourneyActivityViews.swift:145`).

- [ ] **Step 1: Amend the spec**

In `docs/superpowers/specs/2026-08-01-google-nav-journey-screen-design.md`, replace:

```
  showing `ContentState.nextLegLine` ("Then T1 · 8:12 am"). `nextLegLine` is
  already derived for walking and waiting phases and is nil otherwise, so the
  chip hides itself when riding/arrived or when there is no next transit leg.
```

with:

```
  showing `ContentState.nextLegLine` ("Then T1 · 8:12 am"). The chip renders
  only during the walking phase — while waiting, `nextLegLine` names the same
  service as the "Board…" title, so it would duplicate the banner; the Live
  Activity gates its next-leg line to walking for the same reason. It also
  hides when there is no next transit leg.
```

- [ ] **Step 2: Write the failing tests**

Append to `ios/Tests/JourneyBannerModelTests.swift` (the file's `state(...)` helper builds a `ContentState`; `base` is its anchor date):

```swift
    func testWalkingCarriesTheThenChip() {
        let model = JourneyBannerModel.make(
            state: state(phase: .walking, mode: .walk, place: "Chatswood Station", nextLegLine: "Then T1 · 8:12 am"),
            now: base
        )
        XCTAssertEqual(model.thenLine, "Then T1 · 8:12 am")
    }

    func testWaitingSuppressesTheThenChip() {
        // While waiting the banner already says "Board T1…" — the chip would repeat it.
        let model = JourneyBannerModel.make(
            state: state(phase: .waiting, place: "Chatswood, Platform 2", nextLegLine: "Then T1 · 8:12 am"),
            now: base
        )
        XCTAssertNil(model.thenLine)
    }

    func testRidingAndArrivedHaveNoThenChip() {
        XCTAssertNil(JourneyBannerModel.make(state: state(phase: .riding, place: "Central"), now: base).thenLine)
        XCTAssertNil(JourneyBannerModel.make(state: state(phase: .arrived, place: "Central"), now: base).thenLine)
    }
```

- [ ] **Step 3: Implement**

In `JourneyBannerModel` (`ios/Sources/App/UI/JourneyBanner.swift`):

1. Add the property after `let tint: Color`:

```swift
    /// The Google "Then ↱" chip: what follows the current leg. Walking phase only —
    /// while waiting, nextLegLine names the same service the title already boards.
    let thenLine: String?
```

2. In `make(state:now:)`, pass `thenLine:` in every phase's initializer call: `state.nextLegLine` in the `.walking` case, `nil` in `.waiting`, `.riding`, and `.arrived`.

(The struct's memberwise init gains the parameter automatically; `Equatable` synthesis picks it up. The view still compiles because nothing reads `thenLine` yet.)

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/UI/JourneyBanner.swift ios/Tests/JourneyBannerModelTests.swift docs/superpowers/specs/2026-08-01-google-nav-journey-screen-design.md
git commit -m "Derive the Then chip, walking only"
```

---

### Task 3: Floating banner card, chevron deleted

**Files:**
- Modify: `ios/Sources/Shared/Theme.swift`
- Modify: `ios/Sources/App/UI/JourneyBanner.swift` (view — `JourneyBannerView`)
- Modify: `ios/Sources/App/UI/LiveJourneyView.swift` (call site only)

**Interfaces:**
- Consumes: `JourneyBannerModel` incl. `thenLine` (Task 2).
- Produces: `JourneyBannerView(model:)` — **no `onBack` parameter any more**. Task 5 relies on `LiveJourneyView` keeping `@Environment(\.dismiss)` for the Exit pill.

- [ ] **Step 1: Add the banner radius token**

In `Theme.Radius` (`ios/Sources/Shared/Theme.swift`):

```swift
        /// Between pill and card: the floating banner is smaller than a sheet but
        /// rounder than a badge.
        static let banner: CGFloat = 20
```

- [ ] **Step 2: Rebuild `JourneyBannerView`**

Replace the whole `JourneyBannerView` struct in `ios/Sources/App/UI/JourneyBanner.swift` with:

```swift
struct JourneyBannerView: View {
    let model: JourneyBannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s + Theme.Spacing.xs) {
                Image(systemName: model.symbolName)
                    .font(.system(size: 20, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title)
                        .font(.headline)
                        .lineLimit(2)
                    if let subtitle = model.subtitle {
                        Text(subtitle)
                            .font(.footnote.weight(.medium))
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tintCard(Theme.Radius.banner))

            if let thenLine = model.thenLine {
                Text(thenLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(tintCard(Theme.Radius.pill))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: model)
    }

    private func tintCard(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(model.tint)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
```

What changed and why: the edge-to-edge tinted slab (`.background(model.tint.ignoresSafeArea(edges: .top))`) becomes a floating rounded card with the map visible around it; `.title3.bold` drops to `.headline`; the 36 pt chevron button and the `onBack` closure are deleted; the Then chip rides underneath in the same tint.

- [ ] **Step 3: Update the call site**

In `ios/Sources/App/UI/LiveJourneyView.swift`, `topBanner`, replace:

```swift
            JourneyBannerView(model: .make(state: state, now: now), onBack: { dismiss() })
```

with:

```swift
            JourneyBannerView(model: .make(state: state, now: now))
```

Keep `@Environment(\.dismiss)` — Task 5's Exit pill uses it. Update the comment above `.toolbar(.hidden, for: .navigationBar)` from "its back chevron is the way home" to:

```swift
        // No navigation bar: swipe-back (SwipeBackEnabler) and the bar's Exit pill
        // are the ways home.
```

(`SwipeBackEnabler` lands in Task 6; the comment is written once here so the file isn't touched twice.)

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/Shared/Theme.swift ios/Sources/App/UI/JourneyBanner.swift ios/Sources/App/UI/LiveJourneyView.swift
git commit -m "Float the banner and drop the chevron"
```

---

### Task 4: Navigation camera on the map — then push checkpoint 1

**Files:**
- Modify: `ios/Sources/App/Map/JourneyMapView.swift`

**Interfaces:**
- Consumes: `MapFraming.region(for:)`, `CameraMode` reducer (both unchanged).
- Produces, for Task 5:
  - `JourneyMapView(journey:framing:activeLegID:bottomInset:overviewTrigger:)` with `var framing: Framing = .journey` (`enum Framing { case journey, navigation }`) and `var overviewTrigger: Int = 0`. Defaults keep `HomeView` call sites compiling untouched.
  - `MapFraming.navigationDistance: Double` (350).

- [ ] **Step 1: Add the distance constant**

In `enum MapFraming` (`ios/Sources/App/Map/JourneyMapView.swift`):

```swift
    /// Follow height for in-journey navigation: close enough to read street names,
    /// far enough to see the next corner. Google's walking nav sits about here.
    static let navigationDistance: Double = 350
```

- [ ] **Step 2: Add the framing parameter and state**

In `JourneyMapView`, after `let journey: Journey?`:

```swift
    /// How the map frames itself on appear. `.journey` fits the whole route (Home);
    /// `.navigation` zooms to the user at street level and follows (live journey).
    var framing: Framing = .journey

    enum Framing { case journey, navigation }
```

After `var bottomInset: CGFloat = 0`:

```swift
    /// Increment to re-frame the whole journey — the bar's overview button.
    var overviewTrigger: Int = 0
```

With the other `@State` properties:

```swift
    /// Set on the first pan, recenter or overview tap. The first-fix auto-snap into
    /// navigation follow must never fight a camera the user has already taken.
    @State private var userDroveCamera = false
    @State private var navFramed = false
```

- [ ] **Step 3: Split framing into journey and navigation paths**

Replace the existing `frame()` at the bottom of `JourneyMapView` with:

```swift
    private func frame() {
        if framing == .navigation, let coordinate = location.coordinate {
            frameNavigation(on: coordinate)
        } else {
            frameJourney()
        }
    }

    private func frameJourney() {
        guard let journey, let region = MapFraming.region(for: journey) else { return }
        mode = mode.reduced(.journeyFramed)
        withAnimation(.easeInOut(duration: 0.6)) { position = .region(region) }
    }

    private func frameNavigation(on coordinate: CLLocationCoordinate2D) {
        navFramed = true
        mode = .following
        withAnimation(.easeInOut(duration: 0.6)) {
            position = .camera(MapCamera(
                centerCoordinate: coordinate,
                distance: MapFraming.navigationDistance, heading: 0, pitch: 0
            ))
        }
        // .userLocation inherits whatever camera distance is current, so follow can
        // only take over after the zoom-in write has landed.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard mode == .following else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                position = .userLocation(followsHeading: true, fallback: .region(MapFraming.sydney))
            }
        }
    }
```

- [ ] **Step 4: Wire the triggers**

1. In `syncCamera(_:)`, the pan branch marks the camera as user-driven:

```swift
        if position.positionedByUser && mode != .free {
            userDroveCamera = true
            mode = mode.reduced(.userPanned)
        }
```

2. In `recenterButton`'s action, before `apply(...)`:

```swift
                userDroveCamera = true
                apply(mode.reduced(.recenterTapped))
```

3. Replace the coordinate-availability `onChange`:

```swift
        .onChange(of: location.coordinate == nil) { _, unavailable in
            if unavailable {
                mode = mode.reduced(.locationUnavailable)
            } else if framing == .navigation, !navFramed, !userDroveCamera,
                      let coordinate = location.coordinate {
                // The screen opened before the first fix and fell back to the route
                // overview; the fix arriving is the cue to start navigating.
                frameNavigation(on: coordinate)
            }
        }
```

4. Add next to the other `.onChange` modifiers:

```swift
        .onChange(of: overviewTrigger) { _, _ in
            userDroveCamera = true
            frameJourney()
        }
```

- [ ] **Step 5: Commit, push, watch CI**

```bash
git add ios/Sources/App/Map/JourneyMapView.swift
git commit -m "Teach the map to open at street level and follow"
git push -u origin round-4-google-nav-screen
```

Then:

```bash
gh run list --branch round-4-google-nav-screen --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch <run-id> --exit-status
```

Expected: build + unit tests green (new `TimeDisplay` and `JourneyBannerModel` tests pass). Screenshots will still show the old journey framing — `LiveJourneyView` doesn't pass `.navigation` until Task 5; only the banner restyle is visible in `journey.png`. If the run fails, fix before proceeding.

---

### Task 5: The Google bottom bar

**Files:**
- Modify: `ios/Sources/App/UI/LiveJourneyView.swift`

**Interfaces:**
- Consumes: `TimeDisplay.remainingLabel(until:now:)` (Task 1), `JourneyMapView` `framing`/`overviewTrigger` (Task 4), existing `BottomSheet`, `Theme`, `dismiss`.
- Produces: the journey screen's final layout; nothing downstream consumes it.

- [ ] **Step 1: Default the sheet to peek**

Replace the `sheetDetent` declaration (the CI comment moves with it):

```swift
    // Peek by default — Google's compact bar; the journey screenshot starts at
    // .large because CI cannot drag the sheet up.
    @State private var sheetDetent: SheetDetent =
        UserDefaults.standard.string(forKey: "initialScreen") == "journey" ? .large : .peek
```

- [ ] **Step 2: Pass navigation framing and the overview trigger to the map**

Add `@State private var overviewTrigger = 0` beside the other state. Replace the `JourneyMapView` call:

```swift
            JourneyMapView(
                journey: model.selectedJourney,
                framing: .navigation,
                activeLegID: model.selectedJourney?.activeLeg(at: now)?.id,
                bottomInset: bottomContentHeight,
                overviewTrigger: overviewTrigger
            )
```

- [ ] **Step 3: Replace the header with the bar**

Change the sheet's peek closure from `peek: { header(journey) }` to `peek: { bar(journey) }`, then replace the whole `header(_:)` function with:

```swift
    /// Google's navigation bar: the time that matters big on the left, the ways to
    /// step back — overview and Exit — on the right.
    private func bar(_ journey: Journey) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                if let remaining = TimeDisplay.remainingLabel(until: journey.arrival, now: now) {
                    Text(remaining)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText())
                }
                Text(barDetail(journey))
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            Button {
                overviewTrigger += 1
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Colors.surface))
            }
            .buttonStyle(.plain)
            Button {
                dismiss()
            } label: {
                Text("Exit")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.l)
                    .frame(height: 44)
                    .background(Capsule().fill(Theme.Colors.veryLate))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    private func barDetail(_ journey: Journey) -> String {
        let count = journey.transitLegs.count
        let services = "\(count) service\(count == 1 ? "" : "s")"
        guard let arrival = journey.arrival else { return services }
        return "Arrive \(TimeDisplay.clock.string(from: arrival)) · \(services)"
    }
```

Exit pops the screen exactly as the old chevron did — the journey stays selected and resumable from Home ("Tap for live times"), and the Live Activity keeps running. Do not "improve" Exit into `model.reset()`; abandoning the journey is Home's `xmark` button's job.

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/UI/LiveJourneyView.swift
git commit -m "Trade the arrival header for Google's bar"
```

---

### Task 6: Swipe-back with the bar hidden

**Files:**
- Create: `ios/Sources/App/UI/SwipeBackEnabler.swift`
- Modify: `ios/Sources/App/UI/LiveJourneyView.swift` (one modifier)

**Interfaces:**
- Consumes: nothing app-side; UIKit only.
- Produces: `SwipeBackEnabler()`, a zero-size `UIViewControllerRepresentable` attached via `.background`.

- [ ] **Step 1: Create the enabler**

`ios/Sources/App/UI/SwipeBackEnabler.swift`:

```swift
import SwiftUI
import UIKit

/// Hiding the navigation bar also disarms UIKit's edge-swipe pop gesture. This
/// re-arms it for the one screen it is attached to — scoped, unlike the common
/// UINavigationController-category swizzle, so Home keeps stock behaviour and the
/// original delegate comes back when the screen goes away.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Enabler { Enabler() }
    func updateUIViewController(_ controller: Enabler, context: Context) {}

    final class Enabler: UIViewController, UIGestureRecognizerDelegate {
        private weak var gesture: UIGestureRecognizer?
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        // The parent chain doesn't reach the navigation controller until the hosting
        // controller is pushed, so didMove alone can be too early; trying again on
        // every appearance is idempotent via the `gesture == nil` guard.
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            if parent != nil { arm() } else { disarm() }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            arm()
        }

        private func arm() {
            guard gesture == nil,
                  let recognizer = navigationController?.interactivePopGestureRecognizer
            else { return }
            gesture = recognizer
            previousDelegate = recognizer.delegate
            recognizer.delegate = self
        }

        private func disarm() {
            guard let gesture, gesture.delegate === self else { return }
            gesture.delegate = previousDelegate
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Never on the root: popping nothing freezes the navigation controller.
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
```

- [ ] **Step 2: Attach it**

In `ios/Sources/App/UI/LiveJourneyView.swift`, on the outer `ZStack`, directly above `.safeAreaInset(edge: .top, spacing: 0) { topBanner }`:

```swift
        .background(SwipeBackEnabler().allowsHitTesting(false))
```

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/App/UI/SwipeBackEnabler.swift ios/Sources/App/UI/LiveJourneyView.swift
git commit -m "Re-arm swipe-back where the bar is hidden"
```

---

### Task 7: Photograph the walking phase

The `journey` screenshot lands mid-ride (metro demo, boarded six minutes ago), so the Then chip, the walking banner, and the street-level follow would ship unseen. A `walk` screen selects the night demo journey — whose first leg is a walk from Chatswood — at the default peek detent.

**Files:**
- Modify: `ios/Sources/App/DemoJourney.swift`
- Modify: `ios/Sources/App/NextStopApp.swift`
- Modify: `.github/workflows/ios-compile.yml`

**Interfaces:**
- Consumes: `DemoJourney.journeys(around:)` — the night journey's id is `"demo-night"`, first leg `demo-night-walk-in` from (-33.7952, 151.1789).
- Produces: `-initialScreen walk` launch mode; `AppModel.demo(selecting:)`.

- [ ] **Step 1: Let demo select a journey**

In `ios/Sources/App/DemoJourney.swift`, change the `AppModel` extension:

```swift
extension AppModel {
    /// A model pre-loaded with the demo journeys and nothing live behind it — no
    /// network, no ActivityKit — for `-initialScreen options` / `journey` / `walk`
    /// screenshots. `journeyID` picks which demo is live; the metro one otherwise.
    static func demo(selecting journeyID: String? = nil) -> AppModel {
        let model = AppModel(isDemo: true)
        let journeys = DemoJourney.journeys(around: Date())
        model.destination = DemoJourney.destination
        model.journeys = journeys
        model.selectedJourneyID = journeyID ?? journeys.first?.id
        model.phase = .ready
        return model
    }
}
```

- [ ] **Step 2: Route the walk screen**

In `ios/Sources/App/NextStopApp.swift`, `RootView.init`:

```swift
        let demoScreens = ["options", "journey", "medium", "walk"]
        _model = StateObject(
            wrappedValue: requested.map(demoScreens.contains) == true
                ? .demo(selecting: requested == "walk" ? "demo-night" : nil)
                : AppModel()
        )
```

Change the journey branch condition and start the location stream there — without it the provider never publishes a fix, and the navigation camera would sit on its overview fallback in every screenshot:

```swift
        } else if requestedScreen == "journey" || requestedScreen == "walk" {
            NavigationStack {
                LiveJourneyView()
                    .background(Theme.Colors.background)
            }
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.location)
            .preferredColorScheme(.dark)
            .tint(Theme.Colors.textPrimary)
            // The journey screen navigates from the simulator's simulated fix; Home
            // normally starts this stream, but CI jumps straight here.
            .onAppear { model.location.start() }
        } else {
```

(`sheetDetent` in `LiveJourneyView` checks `== "journey"`, so `walk` keeps the peek default — that is the point: the bar must be photographed at rest.)

- [ ] **Step 3: Update the workflow**

In `.github/workflows/ios-compile.yml`:

1. The screen loop gains `walk`:

```yaml
          for screen in home search settings layouts options medium journey walk; do
```

2. The simulated fix moves from the CBD to the night journey's walk origin, so the follow camera opens on the route. There is exactly one `simctl location` line in the workflow; replace its coordinates:

```yaml
          xcrun simctl location "$UDID" set -33.7952,151.1789 || echo "location set failed"
```

- [ ] **Step 4: Commit**

```bash
git add ios/Sources/App/DemoJourney.swift ios/Sources/App/NextStopApp.swift .github/workflows/ios-compile.yml
git commit -m "Photograph the walking phase at street level"
```

---

### Task 8: Push checkpoint 2 — CI, screenshots, PR

**Files:** none (verification and delivery).

- [ ] **Step 1: Push and watch**

```bash
git push
gh run list --branch round-4-google-nav-screen --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch <run-id> --exit-status
```

Expected: green. (Note the workflow only triggers on `ios/**` and the workflow file — Task 7 touched the workflow, so this push triggers.)

- [ ] **Step 2: Download and inspect the screenshots**

```bash
gh run download <run-id> --name simulator-screenshots --dir shots-r4
```

Read `shots-r4/journey.png` and `shots-r4/walk.png` (and skim `home.png`/`medium.png` for regressions — Home must still frame the whole route). Verify against the spec:

- `journey.png`: floating rounded banner card with map visible around it, **no chevron**, riding content ("Alight at…"), no Then chip (riding), sheet at `.large` with the Google bar on top — big remaining time, "Arrive … · 1 service", overview circle, red Exit pill.
- `walk.png`: walking banner ("Walk to Chatswood Station"), **Then chip** ("Then T1 · …"), street-level map around (-33.7952, 151.1789) with the dotted walk polyline and readable street shapes (not the suburb overview), bar at peek height only, map filling the screen between banner and bar.

If a screenshot contradicts the spec, fix and repeat from Step 1. Screenshot failures that are *simulator* artifacts (glass rendering, missing heading rotation) are known-acceptable — judge layout, not materials.

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "Round 4: Google-style journey screen" --body "..."
```

Body: summary of the four changes (banner card + chip, Google bar + Exit, navigation camera, swipe-back), spec path, screenshot notes, and the device checklist from Step 4.

- [ ] **Step 4: Report with the device checklist**

Report to KaiC: what was built, CI status, screenshots reviewed. Device-only checklist (his TestFlight pass):

1. Open a journey during a walking leg — map should zoom to street level on you and rotate as you turn. No pinching needed to see where to walk.
2. Pan the map — camera frees; recenter button cycles centered → heading-follow.
3. Tap the overview button (branch icon) — whole route frames; recenter returns to you.
4. Banner: compact floating card, no back button; "Then T1 · …" chip while walking; chip gone once aboard.
5. Bottom bar: remaining time counts down; drag up still shows all legs; drag down returns to the compact bar.
6. Swipe from the left edge — screen pops back to Home. Exit pill does the same.
7. Force-quit and Live Activity behaviour unchanged from round 3.

---

## Self-Review (completed)

- **Spec coverage:** §1 banner → Tasks 2–3; §2 bar → Tasks 1, 5; §3 camera → Tasks 4–5 (+ CI fix in 7); §4 swipe-back → Task 6; testing section → Tasks 1, 2, 8. Spec's "waiting" chip line amended in Task 2 with rationale.
- **Placeholders:** none — every step carries code or exact commands. PR body in Task 8 is composed at execution time from real results, not a template.
- **Type consistency:** `remainingLabel(until:now:)` (Tasks 1→5); `thenLine` (Tasks 2→3); `Framing`/`framing`/`overviewTrigger`/`navigationDistance` (Tasks 4→5); `demo(selecting:)` (Task 7 internal); `SwipeBackEnabler` (Task 6, named in Task 3's comment).
