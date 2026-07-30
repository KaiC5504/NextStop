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
