import SwiftUI

struct LiveJourneyView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: LocalStore

    @State private var now = Date()
    @State private var lastRefresh = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// The realtime feed itself only moves every 10–15 seconds, so anything faster than this
    /// spends quota to redraw the same numbers.
    private let refreshEvery: TimeInterval = 30

    var body: some View {
        ZStack(alignment: .bottom) {
            JourneyMapView(
                journey: model.selectedJourney,
                activeLegID: model.selectedJourney?.activeLeg(at: now)?.id,
                bottomInset: 460 + Theme.Spacing.s
            )

            if let journey = model.selectedJourney {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(journey)
                        ForEach(Array(journey.legs.enumerated()), id: \.element.id) { index, leg in
                            LegRow(
                                leg: leg,
                                isNext: index == nextLegIndex(journey),
                                now: now,
                                onFeedback: store.ratedLegIDs.contains(leg.id) ? nil : { record(leg, $0) }
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
        // A leg transition is the one moment worth a physical nudge mid-journey.
        .sensoryFeedback(.impact(weight: .medium), trigger: model.selectedJourney?.activeLeg(at: now)?.id)
        .onAppear { model.startJourneyActivity() }
        .onReceive(tick) { instant in
            now = instant
            model.syncJourneyActivity(now: instant)
            if instant.timeIntervalSince(lastRefresh) >= refreshEvery {
                lastRefresh = instant
                Task { await model.refresh() }
            }
        }
    }

    private func header(_ journey: Journey) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let arrival = journey.arrival {
                Text("Arrive \(TimeDisplay.clock.string(from: arrival))")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            if let duration = TimeDisplay.durationLabel(seconds: journey.duration.map(Int.init)) {
                let count = journey.transitLegs.count
                let leave = journey.departure.map { "Leave \(TimeDisplay.clock.string(from: $0)) · " } ?? ""
                Text("\(leave)\(duration) · \(count) service\(count == 1 ? "" : "s")")
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
        withAnimation(.snappy) {
            store.record(PredictionFeedback(leg: leg, wasCorrect: wasCorrect, tappedAt: Date()))
        }
    }
}
