import SwiftUI

struct LegRow: View {
    let leg: Leg
    let isNext: Bool
    let now: Date
    var onFeedback: ((Bool) -> Void)?

    /// Nil until the user decides; the active riding leg auto-expands until then.
    @State private var manuallyExpanded: Bool?

    private var status: DepartureStatus { DepartureStatus(leg: leg) }

    private var isRiding: Bool {
        guard let departure = leg.departure, let arrival = leg.arrival else { return false }
        return departure <= now && now < arrival
    }

    private var isExpanded: Bool { manuallyExpanded ?? isRiding }

    /// Walks show how long they take; transit shows how long until it leaves. The two
    /// used to share a bare "N min" and read as the same quantity.
    private var trailingLabel: String? {
        leg.mode.isWalking
            ? TimeDisplay.durationLabel(seconds: leg.durationSeconds)
            : TimeDisplay.countdownLabel(to: leg.departure, now: now)
    }

    private var hasDeparted: Bool {
        guard let departure = leg.departure else { return false }
        return now > departure
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(spacing: 0) {
                JourneyModeBadge(mode: leg.mode)
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
                    if let trailingLabel {
                        Text(trailingLabel)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(isNext ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .contentTransition(.numericText())
                    }
                }

                if leg.mode.isWalking {
                    Text("to \(leg.destinationName)")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("from \(leg.originName)")
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.tint)
                    if let stopCount = leg.rideStopCount {
                        Button {
                            withAnimation(.snappy) { manuallyExpanded = !isExpanded }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(stopSummary(stopCount))
                                    .font(.footnote)
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            }
                            .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        if isExpanded {
                            TransitStopList(stops: leg.stops, mode: leg.mode, now: now)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
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
        .animation(.snappy, value: isExpanded)
    }

    private func stopSummary(_ count: Int) -> String {
        let stops = "\(count) stop\(count == 1 ? "" : "s")"
        guard let duration = TimeDisplay.durationLabel(seconds: leg.durationSeconds) else { return stops }
        return "\(stops) · \(duration)"
    }
}
