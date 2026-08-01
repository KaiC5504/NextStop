import SwiftUI

/// The next action, big and on top — derived per phase from the same state the Live
/// Activity narrates. This is in-app UI, so unlike ContentState it may vary with `now`.
struct JourneyBannerModel: Equatable {
    let title: String
    let subtitle: String?
    let symbolName: String
    let tint: Color

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
                tint: Theme.Colors.userPuck
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
                tint: state.mode.tint
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
                tint: state.mode.tint
            )
        case .arrived:
            return JourneyBannerModel(
                title: "Arrived",
                subtitle: state.place,
                symbolName: "checkmark.circle.fill",
                tint: Theme.Colors.onTime
            )
        }
    }
}

struct JourneyBannerView: View {
    let model: JourneyBannerModel
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
            Image(systemName: model.symbolName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.tint.ignoresSafeArea(edges: .top))
        .animation(.snappy, value: model)
    }
}
