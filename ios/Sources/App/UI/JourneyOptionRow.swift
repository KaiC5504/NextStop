import SwiftUI

/// Facts for one route row, derived once so they can be asserted without SwiftUI.
struct JourneyOptionRowModel: Equatable {
    let times: String?
    let duration: String?
    let status: DepartureStatus?
    /// "4:32 am from Chatswood Interchange" — the first transit leg's departure, the
    /// same leg the status is judged on.
    let statusDetail: String?

    init(journey: Journey) {
        times = journey.departure.flatMap { departure in
            journey.arrival.map { TimeDisplay.clockRange(from: departure, to: $0) }
        }
        duration = TimeDisplay.longDurationLabel(seconds: journey.duration.map(Int.init))
        let transit = journey.transitLegs.first
        status = transit.map(DepartureStatus.init(leg:))
        statusDetail = transit.flatMap { leg in
            leg.departure.map {
                "\(TimeDisplay.clock.string(from: $0)) from \(StopName.short(leg.originName))"
            }
        }
    }
}

/// One Google-style route row: times with the big duration, the leg sequence, then the
/// realtime status. The sequence degrades stepwise — walk minutes go first, then the
/// walks themselves — instead of ever wrapping a badge.
struct JourneyOptionRow: View {
    let journey: Journey

    private enum SequenceItem {
        case walk(minutes: String?)
        case transit(Leg)
    }

    var body: some View {
        let model = JourneyOptionRowModel(journey: journey)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                if let times = model.times {
                    Text(times)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.s)
                if let duration = model.duration {
                    Text(duration)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            ViewThatFits(in: .horizontal) {
                sequence(items(walkMinutes: true, includeWalks: true))
                sequence(items(walkMinutes: false, includeWalks: true))
                sequence(items(walkMinutes: false, includeWalks: false))
            }
            if let status = model.status {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(status.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.tint)
                    if let detail = model.statusDetail {
                        Text("· \(detail)")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func items(walkMinutes: Bool, includeWalks: Bool) -> [SequenceItem] {
        journey.legs.compactMap { leg in
            guard leg.mode.isWalking else { return .transit(leg) }
            guard includeWalks else { return nil }
            return .walk(minutes: walkMinutes ? TimeDisplay.walkBadgeMinutes(seconds: leg.durationSeconds) : nil)
        }
    }

    private func sequence(_ items: [SequenceItem]) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                switch item {
                case .walk(let minutes):
                    HStack(spacing: 2) {
                        Image(systemName: "figure.walk")
                            .font(.caption)
                        if let minutes {
                            Text(minutes)
                                .font(.caption2.weight(.semibold))
                        }
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                case .transit(let leg):
                    HStack(spacing: 3) {
                        Image(systemName: leg.mode.symbolName)
                            .font(.caption)
                            .foregroundStyle(leg.mode.tint)
                        JourneyRouteCapsule(text: leg.route ?? leg.mode.displayName, tint: leg.mode.tint)
                    }
                }
            }
        }
    }
}
