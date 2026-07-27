import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    private var activity: Activity<SpikeAttributes>?
    private var stateObserver: Task<Void, Never>?
    private let encoder = JSONEncoder()

    var isRunning: Bool { activity != nil }

    func start(_ state: SpikeAttributes.ContentState, name: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            SpikeLog.shared.write("activity.unavailable", "Live Activities are off in Settings")
            return
        }

        do {
            let started = try Activity<SpikeAttributes>.request(
                attributes: SpikeAttributes(sessionName: name),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            activity = started
            SpikeLog.shared.write("activity.started", started.id)
            observeStateChanges(started)
        } catch {
            SpikeLog.shared.write("activity.start.failed", "\(error)")
        }
    }

    func update(_ state: SpikeAttributes.ContentState) async {
        guard let activity else { return }
        // An oversized content state is dropped silently on iOS 26, so the encoded size
        // is measured rather than assumed to be under the 4 KB limit.
        if let encoded = try? encoder.encode(state), encoded.count > 3_500 {
            SpikeLog.shared.write("activity.payload.large", "\(encoded.count) bytes")
        }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end() async {
        stateObserver?.cancel()
        stateObserver = nil
        guard let activity else { return }
        let id = activity.id
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        SpikeLog.shared.write("activity.ended", id)
    }

    /// The system can cull an activity on its own. Without this the log would show ticks
    /// continuing against an activity that no longer exists, which reads like a pass.
    private func observeStateChanges(_ activity: Activity<SpikeAttributes>) {
        stateObserver = Task {
            for await state in activity.activityStateUpdates {
                SpikeLog.shared.write("activity.state", "\(state)")
            }
        }
    }
}
