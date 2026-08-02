import SwiftUI

struct LiveJourneyView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: LocalStore

    @Environment(\.dismiss) private var dismiss

    @State private var now = Date()
    @State private var lastRefresh = Date()
    @State private var bottomContentHeight: CGFloat = 0
    // Peek by default — Google's compact bar; the journey screenshot starts at
    // .large because CI cannot drag the sheet up.
    @State private var sheetDetent: SheetDetent =
        UserDefaults.standard.string(forKey: "initialScreen") == "journey" ? .large : .peek
    @State private var sheetDragging = false
    @State private var overviewTrigger = 0
    /// Stable per-appearance anchor for the banner's state derivation — the activity's
    /// own start time is private to the model and never set in demo mode.
    @State private var appearedAt = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// The realtime feed itself only moves every 10–15 seconds, so anything faster than this
    /// spends quota to redraw the same numbers.
    private let refreshEvery: TimeInterval = 30

    var body: some View {
        ZStack(alignment: .bottom) {
            JourneyMapView(
                journey: model.selectedJourney,
                framing: .navigation,
                activeLegID: model.selectedJourney?.activeLeg(at: now)?.id,
                bottomInset: bottomContentHeight,
                overviewTrigger: overviewTrigger
            )

            if let journey = model.selectedJourney {
                BottomSheet(
                    detent: $sheetDetent,
                    onRestingHeight: { height in
                        withAnimation(SheetPhysics.spring) { bottomContentHeight = height }
                    },
                    onDragChanged: { sheetDragging = $0 },
                    peek: { bar(journey) },
                    more: {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(journey.legs.enumerated()), id: \.element.id) { index, leg in
                                    LegRow(
                                        leg: leg,
                                        isNext: index == nextLegIndex(journey),
                                        now: now,
                                        onFeedback: store.ratedLegIDs.contains(leg.id) ? nil : { record(leg, $0) }
                                    )
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.m)
                        }
                        .scrollIndicators(.hidden)
                        // Sheet drags at medium, list scrolls at large — same split as Home.
                        .scrollDisabled(sheetDetent != .large)
                        .frame(maxHeight: 520)
                    }
                )
            }
        }
        .background(SwipeBackEnabler().allowsHitTesting(false))
        .safeAreaInset(edge: .top, spacing: 0) { topBanner }
        // No navigation bar: swipe-back (SwipeBackEnabler) and the bar's Exit pill
        // are the ways home.
        .toolbar(.hidden, for: .navigationBar)
        // A leg transition is the one moment worth a physical nudge mid-journey.
        .sensoryFeedback(.impact(weight: .medium), trigger: model.selectedJourney?.activeLeg(at: now)?.id)
        .onAppear { model.startJourneyActivity() }
        .onReceive(tick) { instant in
            // A tick mid-drag re-morphs every countdown and rebuilds the map content
            // under the finger; the drag lasts well under a second, so skipping is free.
            guard !sheetDragging else { return }
            now = instant
            model.syncJourneyActivity(now: instant)
            if instant.timeIntervalSince(lastRefresh) >= refreshEvery {
                lastRefresh = instant
                Task { await model.refresh() }
            }
        }
    }

    @ViewBuilder
    private var topBanner: some View {
        if let journey = model.selectedJourney,
           let destination = model.destination,
           let state = JourneyActivityState.make(
               journey: journey, destinationName: destination.name,
               startedAt: appearedAt, now: now
           ) {
            JourneyBannerView(model: .make(state: state, now: now))
        }
    }

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

    private func nextLegIndex(_ journey: Journey) -> Int? {
        journey.legs.firstIndex { ($0.departure ?? .distantPast) > now }
    }

    private func record(_ leg: Leg, _ wasCorrect: Bool) {
        withAnimation(.snappy) {
            store.record(PredictionFeedback(leg: leg, wasCorrect: wasCorrect, tappedAt: Date()))
        }
    }
}
