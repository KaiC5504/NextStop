import SwiftUI

/// The journey Live Activity presentations, shared between the widget extension that
/// ships them and the in-app harness that previews them — same arrangement as the spike
/// views, for the same reason: no previews exist on a remote build machine, so the app
/// itself has to be able to render what the widget will show.
///
/// Every countdown is a self-ticking `Text(timerInterval:)` against the state's fixed
/// Dates. It keeps counting honestly with zero updates and floors at 0:00 instead of
/// inventing negative time.

extension JourneyActivityPhase {
    var verb: String {
        switch self {
        case .waiting: "Board"
        case .riding: "Alight at"
        case .walking: "Walk to"
        case .arrived: "Arrived at"
        }
    }
}

/// Mirrors the leg list's mode circle so the Lock Screen reads as the same app.
struct JourneyModeBadge: View {
    let mode: TransitMode

    var body: some View {
        Image(systemName: mode.symbolName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(mode.isWalking ? Theme.Colors.textSecondary : .white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(mode.tint.opacity(mode.isWalking ? 0.15 : 1)))
    }
}

struct JourneyRouteCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint))
            .foregroundStyle(.white)
    }
}

struct JourneyLockScreenView: View {
    let state: JourneyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                JourneyModeBadge(mode: state.mode)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let route = state.routeBadge {
                            JourneyRouteCapsule(text: route, tint: state.mode.tint)
                        }
                        Text("\(state.phase.verb) \(state.place)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    // Aboard, the headsign has done its job — which station is next is
                    // the fact the rider actually wants.
                    if state.phase == .riding, let nextStop = state.nextStopName {
                        Text("Next stop \(nextStop)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let headsign = state.headsign {
                        Text(headsign)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    countdown
                    Text("leg \(state.legIndex) of \(state.legCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let stopIndex = state.stopIndex, let stopCount = state.stopCount {
                        Text("stop \(stopIndex) of \(stopCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                statusLine
                Spacer(minLength: 8)
                Text("Arrive \(state.arrivalShort)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if state.phase != .arrived {
                JourneyProgressBar(state: state, isStale: isStale)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var countdown: some View {
        if state.phase == .arrived {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text("Arrived")
            }
            .font(.headline.weight(.bold))
            .foregroundStyle(Theme.Colors.onTime)
        } else {
            Text(timerInterval: state.countdownStart...state.countdownEnd, countsDown: true)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    /// While walking, the connection line replaces the status — the status shown IS the
    /// connection's, and "Then T1 · 5:12 pm" is the fact the walker needs.
    @ViewBuilder
    private var statusLine: some View {
        if isStale {
            Text("May be out of date")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.noRealtime)
        } else if state.phase == .walking, let next = state.nextLegLine {
            Text(next)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.status.tint)
        } else {
            Text(state.status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.status.tint)
        }
    }
}

struct JourneyProgressBar: View {
    let state: JourneyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        // Explicit empty labels: the timer variant of ProgressView renders its own
        // time text otherwise, duplicating the countdown above it.
        ProgressView(timerInterval: state.countdownStart...state.countdownEnd, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(isStale ? Theme.Colors.noRealtime : state.mode.tint)
        // Station ticks. The fractions are computed against the same two anchors the
        // timer animates over, so the fill edge crosses each tick at exactly that stop's
        // scheduled moment — station progress with zero extra updates.
        .overlay {
            if let fractions = state.stopFractions, !fractions.isEmpty {
                GeometryReader { geo in
                    ForEach(fractions, id: \.self) { fraction in
                        Capsule()
                            .fill(Theme.Colors.background.opacity(0.9))
                            .frame(width: 2, height: 4)
                            .position(x: CGFloat(fraction) * geo.size.width, y: geo.size.height / 2)
                    }
                }
            }
        }
    }
}

struct JourneyCompactLeadingView: View {
    let state: JourneyActivityAttributes.ContentState

    var body: some View {
        // Symbol only. Route text runs to four-plus characters ("601X") and the compact
        // slot cannot spare the width.
        Image(systemName: state.mode.symbolName)
            .foregroundStyle(state.mode.isWalking ? Color.white : state.mode.tint)
    }
}

struct JourneyCompactTrailingView: View {
    let state: JourneyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if state.phase == .arrived {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.onTime)
        } else {
            // The width cap is load-bearing: timer text greedily reserves space in the
            // compact slot and pushes the island apart without it.
            Text(timerInterval: state.countdownStart...state.countdownEnd, countsDown: true, showsHours: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 44)
                .foregroundStyle(isStale ? Theme.Colors.noRealtime : state.status.tint)
        }
    }
}

struct JourneyMinimalView: View {
    let state: JourneyActivityAttributes.ContentState

    var body: some View {
        if state.phase == .arrived {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.onTime)
        } else {
            Image(systemName: state.mode.symbolName)
                .foregroundStyle(state.mode.isWalking ? Color.white : state.mode.tint)
        }
    }
}

struct JourneyExpandedLeadingView: View {
    let state: JourneyActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            JourneyModeBadge(mode: state.mode)
            if let route = state.routeBadge {
                JourneyRouteCapsule(text: route, tint: state.mode.tint)
            }
        }
    }
}

struct JourneyExpandedTrailingView: View {
    let state: JourneyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if state.phase == .arrived {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Arrived")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Colors.onTime)
            } else {
                Text(timerInterval: state.countdownStart...state.countdownEnd, countsDown: true)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                    .foregroundStyle(.white)
            }
            Text(isStale ? "May be out of date" : state.status.label)
                .font(.caption2)
                .foregroundStyle(isStale ? Theme.Colors.noRealtime : state.status.tint)
        }
    }
}

struct JourneyExpandedBottomView: View {
    let state: JourneyActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(state.phase.verb) \(state.place)")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(trailingSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if state.phase != .arrived {
                JourneyProgressBar(state: state, isStale: isStale)
            }
        }
    }

    private var trailingSummary: String {
        var parts = ["arr \(state.arrivalShort)", "leg \(state.legIndex)/\(state.legCount)"]
        if let stopIndex = state.stopIndex, let stopCount = state.stopCount {
            parts.append("stop \(stopIndex)/\(stopCount)")
        }
        return parts.joined(separator: " · ")
    }
}
