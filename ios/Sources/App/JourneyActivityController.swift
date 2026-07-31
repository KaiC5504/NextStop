import ActivityKit
import Foundation

/// Owns the journey Live Activity. Mirrors the spike controller rather than genericising
/// it: the spike is device-verified experiment code and stays untouched as the control.
@MainActor
final class JourneyActivityController {
    /// Six missed refresh cycles. Never trips while the app is foreground and syncing,
    /// but marks a backgrounded app's activity as unreliable within minutes instead of
    /// letting it claim live estimates for a whole commute.
    private let staleAfter: TimeInterval = 180

    private var activity: Activity<JourneyActivityAttributes>?
    private var lastSent: JourneyActivityAttributes.ContentState?
    private var lastSentAt: Date?
    /// Set when starting is pointless (activities disabled, request threw). Without it
    /// the 1-second sync tick would retry — and log — every second.
    private var startDeclined = false
    /// Re-entrancy latch: sync suspends at ActivityKit calls, and the next tick must not
    /// interleave a second start or end into that gap. A skipped tick costs nothing.
    private var syncing = false
    private let encoder = JSONEncoder()

    var isRunning: Bool { activity != nil }

    /// An activity that survived a force-quit narrates a journey the app no longer
    /// remembers — nothing persists journey state — so the only honest move is to end it.
    func sweepOrphans() async {
        for orphan in Activity<JourneyActivityAttributes>.activities {
            await orphan.end(nil, dismissalPolicy: .immediate)
            SpikeLog.shared.write("journey.activity.orphan", orphan.id)
        }
    }

    func sync(state: JourneyActivityAttributes.ContentState, destinationName: String, startedAt: Date) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }

        if let running = activity, running.attributes.destinationName != destinationName {
            await end()
        }
        guard let activity else {
            if !startDeclined {
                start(state: state, destinationName: destinationName, startedAt: startedAt)
            }
            return
        }
        if state == lastSent,
           !ActivityHeartbeat.shouldResend(lastSentAt: lastSentAt, now: Date(), staleAfter: staleAfter) {
            return
        }
        lastSent = state
        lastSentAt = Date()
        checkPayload(state)
        await activity.update(content(for: state))
    }

    /// Ends with the final state left on screen: the banner lingers as arrival
    /// confirmation rather than vanishing the moment it becomes true.
    func endArrived(finalState: JourneyActivityAttributes.ContentState) async {
        guard let activity else { return }
        let id = activity.id
        self.activity = nil
        lastSent = nil
        lastSentAt = nil
        await activity.end(content(for: finalState), dismissalPolicy: .after(Date().addingTimeInterval(300)))
        SpikeLog.shared.write("journey.activity.arrived", id)
    }

    func end() async {
        guard let activity else { return }
        let id = activity.id
        self.activity = nil
        lastSent = nil
        lastSentAt = nil
        startDeclined = false
        await activity.end(nil, dismissalPolicy: .immediate)
        SpikeLog.shared.write("journey.activity.ended", id)
    }

    private func start(state: JourneyActivityAttributes.ContentState, destinationName: String, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            startDeclined = true
            SpikeLog.shared.write("journey.activity.unavailable", "Live Activities are off in Settings")
            return
        }
        checkPayload(state)
        do {
            let started = try Activity<JourneyActivityAttributes>.request(
                attributes: JourneyActivityAttributes(destinationName: destinationName, startedAt: startedAt),
                content: content(for: state),
                pushType: nil
            )
            activity = started
            lastSent = state
            lastSentAt = Date()
            SpikeLog.shared.write("journey.activity.started", started.id)
        } catch {
            startDeclined = true
            SpikeLog.shared.write("journey.activity.start.failed", "\(error)")
        }
    }

    private func content(for state: JourneyActivityAttributes.ContentState) -> ActivityContent<JourneyActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter))
    }

    /// An oversized content state is dropped silently on iOS 26, so the encoded size is
    /// measured rather than assumed to be under the 4 KB limit.
    private func checkPayload(_ state: JourneyActivityAttributes.ContentState) {
        if let encoded = try? encoder.encode(state), encoded.count > 3_500 {
            SpikeLog.shared.write("journey.activity.payload.large", "\(encoded.count) bytes")
        }
    }
}
