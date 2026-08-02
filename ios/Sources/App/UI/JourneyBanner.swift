import SwiftUI

/// The next action, big and on top — derived per phase from the same state the Live
/// Activity narrates. This is in-app UI, so unlike ContentState it may vary with `now`.
struct JourneyBannerModel: Equatable {
    let title: String
    let subtitle: String?
    let symbolName: String
    let tint: Color
    /// The Google "Then ↱" chip: what follows the current leg. Walking phase only —
    /// while waiting, nextLegLine names the same service the title already boards.
    let thenLine: String?

    static func make(state: JourneyActivityAttributes.ContentState, now: Date) -> JourneyBannerModel {
        switch state.phase {
        case .walking:
            return JourneyBannerModel(
                title: "Walk to \(StopName.short(state.place))",
                subtitle: TimeDisplay.durationLabel(
                    seconds: Int(state.countdownEnd.timeIntervalSince(now))
                ) ?? state.nextLegLine,
                symbolName: "figure.walk",
                // Walk-grey is illegible as a banner surface; the puck blue reads as
                // "you, moving" everywhere else in the app.
                tint: Theme.Colors.userPuck,
                thenLine: state.nextLegLine
            )
        case .waiting:
            let route = state.routeBadge ?? state.mode.displayName
            let headsign = state.headsign.map { " to \($0)" } ?? ""
            let parts = [
                TimeDisplay.countdownLabel(to: state.countdownEnd, now: now),
                StopName.platform(state.place),
            ].compactMap { $0 }
            return JourneyBannerModel(
                title: "Board \(route)\(headsign)",
                subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                symbolName: state.mode.symbolName,
                tint: state.mode.tint,
                thenLine: nil
            )
        case .riding:
            var subtitle = state.status.label
            if let next = state.nextStopName, let index = state.stopIndex, let count = state.stopCount {
                subtitle = "Next stop \(next) · stop \(index) of \(count)"
            }
            return JourneyBannerModel(
                title: "Alight at \(StopName.short(state.place))",
                subtitle: subtitle,
                symbolName: state.mode.symbolName,
                tint: state.mode.tint,
                thenLine: nil
            )
        case .arrived:
            return JourneyBannerModel(
                title: "Arrived",
                subtitle: state.place,
                symbolName: "checkmark.circle.fill",
                tint: Theme.Colors.onTime,
                thenLine: nil
            )
        }
    }
}

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
