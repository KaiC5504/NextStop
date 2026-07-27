import CoreLocation
import Foundation
import Observation

/// Orchestrates one experiment: hold the process alive, tick a Live Activity, measure
/// the largest gap between ticks.
///
/// The gap is the entire result. A tick every 5 seconds that never gaps by more than a
/// few means iOS kept the app running; a 40-minute gap starting the moment the screen
/// locked means it did not, and the log says which mechanism was in play.
@MainActor
@Observable
final class SpikeSession {
    var mechanism: HoldMechanism = .backgroundActivitySession
    var interval: TimeInterval = 5

    private(set) var isRunning = false
    private(set) var tick = 0
    private(set) var maxGap: TimeInterval = 0
    private(set) var startedAt: Date?
    private(set) var lastTickAt: Date?

    private var holder: ExecutionHolder?
    private var tickTask: Task<Void, Never>?
    private let activities = LiveActivityController()
    private let authManager = CLLocationManager()

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var fixAge: TimeInterval? {
        holder?.lastFix.map { Date().timeIntervalSince($0) }
    }

    var verdict: String {
        guard tick > 0 else { return "—" }
        return maxGap <= SpikeAttributes.ContentState.gapBudget ? "PASS" : "FAIL"
    }

    func start() {
        guard !isRunning else { return }
        HolderFactory.requestAuthorization(authManager)

        tick = 0
        maxGap = 0
        let now = Date()
        startedAt = now
        lastTickAt = now
        isRunning = true

        let made = HolderFactory.make(mechanism)
        holder = made
        made.start()

        SpikeLog.shared.write(
            "session.start",
            "mechanism=\(mechanism.rawValue) interval=\(Int(interval))s"
        )
        activities.start(state(at: now), name: mechanism.title)

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.interval))
                if Task.isCancelled { return }
                await self.tickOnce()
            }
        }
    }

    func stop() async {
        tickTask?.cancel()
        tickTask = nil
        holder?.stop()
        holder = nil
        await activities.end()
        isRunning = false
        SpikeLog.shared.write(
            "session.stop",
            "ticks=\(tick) maxGap=\(String(format: "%.1f", maxGap))s verdict=\(verdict)"
        )
    }

    func noteScenePhase(_ phase: String) {
        SpikeLog.shared.write("scene.\(phase)", "tick=\(tick)")
    }

    private func tickOnce() async {
        let now = Date()
        if let last = lastTickAt {
            let gap = now.timeIntervalSince(last)
            maxGap = max(maxGap, gap)
            // Anything past twice the interval means at least one tick was missed, which
            // is the event worth finding in a 400-line log.
            if gap > interval * 2 {
                SpikeLog.shared.write("gap", String(format: "%.1fs after tick %d", gap, tick))
            }
        }
        lastTickAt = now
        tick += 1

        let current = state(at: now)
        await activities.update(current)

        let fix = current.fixAge.map { String(format: "%.0fs", $0) } ?? "none"
        SpikeLog.shared.write(
            "tick",
            "n=\(tick) fix=\(fix) maxGap=\(String(format: "%.1f", maxGap))s"
        )
    }

    private func state(at moment: Date) -> SpikeAttributes.ContentState {
        SpikeAttributes.ContentState(
            tick: tick,
            updatedAt: moment,
            startedAt: startedAt ?? moment,
            mechanism: mechanism.title,
            fixAge: holder?.lastFix.map { moment.timeIntervalSince($0) },
            maxGap: maxGap
        )
    }
}
