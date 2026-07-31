import SwiftUI

/// The vertical route list in the Home sheet: one row per alternative, Google style —
/// leg sequence, clocks, then status · duration · walk.
struct JourneyOptionsList: View {
    @EnvironmentObject private var model: AppModel
    let detent: SheetDetent
    /// Called after a tap has set the selection; the caller owns navigation.
    var onOpen: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Routes")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    PlanTimeControl()
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.s)

                ForEach(model.journeys) { journey in
                    row(journey)
                    if journey.id != model.journeys.last?.id {
                        Divider().overlay(Theme.Colors.stroke)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
        }
        .scrollIndicators(.hidden)
        // At medium a vertical swipe drags the sheet; only the large detent scrolls the
        // list, so the two gestures never fight.
        .scrollDisabled(detent != .large)
        .frame(maxHeight: 480)
        .sensoryFeedback(.selection, trigger: model.selectedJourneyID)
    }

    private func row(_ journey: Journey) -> some View {
        let selected = journey.id == model.selectedJourneyID
        return Button {
            withAnimation(.snappy) { model.selectedJourneyID = journey.id }
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    legSequence(journey)
                    Spacer(minLength: Theme.Spacing.s)
                    if let departure = journey.departure, let arrival = journey.arrival {
                        Text("\(TimeDisplay.clock.string(from: departure)) → \(TimeDisplay.clock.string(from: arrival))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: Theme.Spacing.xs) {
                    if let status = journey.transitLegs.first.map({ DepartureStatus(leg: $0) }) {
                        Text(status.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.tint)
                    }
                    if let duration = TimeDisplay.durationLabel(seconds: journey.duration.map(Int.init)) {
                        Text("· \(duration)")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    if let walk = TimeDisplay.durationLabel(seconds: journey.totalWalkSeconds) {
                        Text("· \(walk) walk")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(selected ? Theme.Colors.surface : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .strokeBorder(selected ? Theme.Colors.textPrimary : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: selected)
    }

    private func legSequence(_ journey: Journey) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(journey.legs.enumerated()), id: \.element.id) { index, leg in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if leg.mode.isWalking {
                    Image(systemName: "figure.walk")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    JourneyRouteCapsule(text: leg.route ?? leg.mode.displayName, tint: leg.mode.tint)
                }
            }
        }
    }
}
