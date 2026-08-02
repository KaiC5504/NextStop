# Google-style journey screen (device feedback round 4)

Date: 2026-08-01
Status: approved by KaiC (banner card + Then chip, Google bottom bar with Exit,
street-level follow camera, swipe-back fix)

## Problem

Device comparison of `LiveJourneyView` against Google Maps walking navigation
(Chatswood screenshots, 2026-08-01) surfaced three complaints:

1. **Map too zoomed out.** `JourneyMapView.frame()` frames the *entire journey*
   when the screen opens, so a 46-minute trip renders at suburb scale. Google
   follows the user at street level during navigation; KaiC has to pinch-zoom
   manually every time to see where to walk.
2. **Chrome eats the map.** The top banner is a full-width opaque slab (36 pt
   back chevron, `.title3` bold title, `Theme.Spacing.m` padding, tint extended
   through the status bar) and the bottom sheet opens at `.medium` (summary plus
   260 pt of the legs list). Google's equivalents are a floating rounded card
   and a single compact bar.
3. **Back chevron is unwanted.** KaiC expects iOS swipe-back. Today the chevron
   is the *only* way back: `.toolbar(.hidden, for: .navigationBar)` disables the
   interactive pop gesture, so swipe-back does not work on this screen at all.

Direction: copy Google Maps' navigation layout. Their design is the reference;
we deviate only where our data model forces it (TfNSW gives legs, not
turn-by-turn maneuvers, so banner content stays leg-level).

## Decisions (locked with KaiC)

- Exit affordance: red **Exit** pill in the bottom bar (Google parity) *plus*
  working swipe-back. Back chevron deleted.
- Default camera on the journey screen: **heading-up follow at street level**
  (Google walking nav). Not north-up, not journey overview.
- **"Then" chip** under the banner ships this round.

## Design

### 1. Top banner → floating card + Then chip

`JourneyBannerView` becomes a rounded floating card with horizontal margins —
map visible around it — instead of an edge-to-edge tinted slab.

- Delete the back chevron and the `onBack` parameter entirely.
- One compact row: mode symbol, title in `.headline` (down from `.title3`
  bold), subtitle in `.footnote`. Title keeps a 2-line limit for long stop
  names; padding drops to compact (`Theme.Spacing.s`-class) values.
- Tinted background stays phase-driven (puck blue walking, mode tint
  waiting/riding, green arrived) at the existing corner-radius idiom
  (`Theme.Radius`).
- **Then chip:** a small left-aligned chip below the card, same tint family,
  showing `ContentState.nextLegLine` ("Then T1 · 8:12 am"). The chip renders
  only during the walking phase — while waiting, `nextLegLine` names the same
  service as the "Board…" title, so it would duplicate the banner; the Live
  Activity gates its next-leg line to walking for the same reason. It also
  hides when there is no next transit leg.
- `JourneyBannerModel` gains the chip line so the mapping stays pure and
  testable; phase→title/subtitle/symbol/tint logic is otherwise unchanged.

### 2. Bottom sheet → Google bottom bar

The sheet keeps its physics, detents and legs list. Only the default detent and
the peek content change.

- Default detent becomes `.peek` (was `.medium`). The CI journey screenshot
  still forces `.large` via `-initialScreen journey`.
- Peek content is rebuilt as Google's bar:
  - Left column: **time remaining to arrival**, big (`.title2` bold — "46
    min"), with "Arrive 5:02 pm · 2 services" in `.footnote` beneath.
  - Right side: an **overview button** (route-overview glyph) that frames the
    whole journey on the map — the old default framing, now on demand — and a
    red **Exit** pill that pops back to Home.
- Remaining time ticks off `now` (already re-rendered per second). Formatting
  is a pure `TimeDisplay` function: minutes-granularity duration until
  `journey.arrival`; at/after arrival it reads "Arrived". If `journey.arrival`
  is nil, fall back to the journey duration label; if both are missing the big
  line is omitted and the footnote row alone shows.
- Dragging up still reveals the full legs list at `.medium`/`.large` exactly as
  today, including the feedback buttons.

### 3. Camera → navigation follow

`JourneyMapView` gains a per-host initial framing mode; the map itself stays
shared.

- New parameter (e.g. `framing: .journey | .navigation`). Home keeps
  `.journey` (frame the whole route). `LiveJourneyView` passes `.navigation`.
- `.navigation` on appear: write an explicit `MapCamera` centred on the user at
  ~350 m altitude, then hand off to `.userLocation(followsHeading: true)`;
  `CameraMode` starts at `.following`. (The two-step write exists because
  `.userLocation` preserves the current camera distance — handing off without
  the explicit camera would follow at suburb zoom.)
- No location fix → fall back to whole-journey framing; if the first fix
  arrives before the user has panned or tapped recenter, snap to navigation
  follow then.
- Existing behaviour preserved: pan breaks to `.free`, recenter cycles
  `centered ↔ following`, `locationUnavailable` drops to `.free`.
- The overview button in the bottom bar emits the existing `journeyFramed`
  event (mode → `.free`) and animates to `MapFraming.region(for:)` — same code
  path as today's on-appear framing.

### 4. Swipe-back

A scoped shim (`SwipeBackEnabler`, a zero-size `UIViewControllerRepresentable`
attached to the journey screen) re-enables `interactivePopGestureRecognizer`
while the navigation bar is hidden — chosen over the common app-wide
`UINavigationController`-category swizzle so Home keeps stock behaviour and
the original delegate is restored on teardown. It refuses the gesture at the
stack root (`viewControllers.count > 1`) and while a push/pop transition is
in flight (`transitionCoordinator == nil`), matching UIKit's own refusals.

## Error handling

- `journey.arrival` nil → duration fallback, then footnote-only (above).
- No location fix on the journey screen → journey overview framing, unchanged
  recenter-button hiding (`location.coordinate == nil`).
- `JourneyActivityState.make` returning nil (no banner) leaves the map and bar
  functional; unchanged from today.

## Testing

Pure logic first, chrome verified by CI screenshots, feel verified on device.

- `JourneyBannerModelTests`: chip line present while walking/waiting with a
  next leg, absent riding/arrived/no-next-leg; no chevron affordance left.
- `TimeDisplayTests`: remaining-time formatting — future arrival, past arrival
  ("Arrived"), nil arrival fallback.
- `CameraModeTests`: initial `.following` entry for navigation framing and the
  overview event path stay within the existing reducer table.
- CI screenshots: journey.png re-verified — floating compact banner, no
  chevron, Google bar with Exit pill (sheet forced `.large` as today).
- Device-only checklist: follow-camera zoom level and rotation feel, handoff
  from explicit camera to heading follow, swipe-back gesture, Exit pill,
  overview button framing, Then chip during a real walking leg.

## Out of scope

Home screen layout (unchanged this round), live vehicle dots (queued, needs
VPS GTFS-RT proxy), service alerts, APNs push, turn-by-turn walking maneuvers
(no data source).
