import SwiftUI

/// The expanded stations under a transit leg: every stop after boarding (the boarding
/// stop is the leg row's "from X"), with a spine that fills to the ride's position.
/// Fixed row heights keep the dots, the spine and the labels aligned by arithmetic
/// instead of GeometryReader.
struct TransitStopList: View {
    let stops: [LegStop]
    let mode: TransitMode
    let now: Date

    private static let rowHeight: CGFloat = 28
    private static let dotSize: CGFloat = 8

    private var shown: [LegStop] { Array(stops.dropFirst()) }
    /// Arrival at a stop is the moment the fill should touch its dot.
    private var times: [Date] { stops.compactMap { $0.arrival ?? $0.departure } }
    /// Dot centre to dot centre.
    private var trackHeight: CGFloat { Self.rowHeight * CGFloat(max(shown.count - 1, 0)) }

    private var fillFraction: Double {
        StopProgress.spineFillFraction(
            position: StopProgress.position(times: times, now: now),
            stopCount: stops.count
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            ZStack(alignment: .top) {
                Capsule()
                    .fill(mode.tint.opacity(0.25))
                    .frame(width: 2, height: trackHeight)
                    .offset(y: Self.rowHeight / 2)
                Capsule()
                    .fill(mode.tint)
                    .frame(width: 2, height: trackHeight * fillFraction)
                    .offset(y: Self.rowHeight / 2)
                VStack(spacing: 0) {
                    ForEach(shown) { stop in
                        dot(filled: passed(stop))
                            .frame(width: Self.dotSize, height: Self.rowHeight)
                    }
                }
            }
            .frame(width: Self.dotSize)

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, stop in
                    let isAlight = index == shown.count - 1
                    HStack(spacing: Theme.Spacing.s) {
                        Text(stop.name)
                            .font(.footnote.weight(isAlight ? .semibold : .regular))
                            .foregroundStyle(isAlight ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Spacing.s)
                        if let time = stop.arrival ?? stop.departure {
                            Text(TimeDisplay.clock.string(from: time))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .frame(height: Self.rowHeight)
                }
            }
        }
    }

    private func passed(_ stop: LegStop) -> Bool {
        (stop.arrival ?? stop.departure).map { $0 <= now } == true
    }

    private func dot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? mode.tint : Theme.Colors.background)
            .overlay(Circle().strokeBorder(mode.tint, lineWidth: 1.5))
            .frame(width: Self.dotSize, height: Self.dotSize)
    }
}
