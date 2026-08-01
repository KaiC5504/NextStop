import SwiftUI

/// The expanded stations under a transit leg: every stop after boarding (the boarding
/// stop is the leg row's "from X"), with a spine that fills to the ride's position.
/// Intermediates are one quiet line each — cleaned name and time — and the alighting
/// stop gets a taller, louder row with its platform, because that's the one decision
/// the rider has to act on. Fixed row heights keep the dots, the spine and the labels
/// aligned by arithmetic instead of GeometryReader.
struct TransitStopList: View {
    let stops: [LegStop]
    let mode: TransitMode
    let now: Date

    private static let rowHeight: CGFloat = 28
    private static let alightRowHeight: CGFloat = 56
    private static let dotSize: CGFloat = 8
    private static let alightDotSize: CGFloat = 10

    private var shown: [LegStop] { Array(stops.dropFirst()) }
    private var intermediates: [LegStop] { Array(shown.dropLast()) }
    private var alight: LegStop? { shown.last }
    /// Arrival at a stop is the moment the fill should touch its dot.
    private var times: [Date] { stops.compactMap { $0.arrival ?? $0.departure } }

    private var trackHeight: CGFloat {
        spineHeight(position: Double(stops.count - 1))
    }

    private var fillHeight: CGFloat {
        spineHeight(position: StopProgress.position(times: times, now: now))
    }

    private func spineHeight(position: Double) -> CGFloat {
        CGFloat(StopProgress.spineFillHeight(
            position: position, stopCount: stops.count,
            rowHeight: Self.rowHeight, finalRowHeight: Self.alightRowHeight
        ))
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
                    .frame(width: 2, height: fillHeight)
                    .offset(y: Self.rowHeight / 2)
                VStack(spacing: 0) {
                    ForEach(intermediates) { stop in
                        dot(filled: passed(stop))
                            .frame(width: Self.dotSize, height: Self.rowHeight)
                    }
                    if let alight {
                        alightDot(filled: passed(alight))
                            .frame(width: Self.alightDotSize, height: Self.alightRowHeight)
                    }
                }
            }
            .frame(width: Self.alightDotSize)

            VStack(spacing: 0) {
                ForEach(intermediates) { stop in
                    HStack(spacing: Theme.Spacing.s) {
                        Text(StopName.short(stop.name))
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.textSecondary)
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
                if let alight {
                    HStack(spacing: Theme.Spacing.s) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(StopName.short(alight.name))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(2)
                            if let platform = StopName.platform(alight.name) {
                                Text(platform)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        Spacer(minLength: Theme.Spacing.s)
                        if let time = alight.arrival ?? alight.departure {
                            Text(TimeDisplay.clock.string(from: time))
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                    .frame(height: Self.alightRowHeight)
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

    private func alightDot(filled: Bool) -> some View {
        Circle()
            .fill(filled ? mode.tint : Theme.Colors.background)
            .overlay(Circle().strokeBorder(mode.tint, lineWidth: 2))
            .frame(width: Self.alightDotSize, height: Self.alightDotSize)
    }
}
