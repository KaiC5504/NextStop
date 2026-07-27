import ActivityKit
import Foundation

let appGroupIdentifier = "group.com.kaichuan.nextstop"

/// Live Activity payload for the Phase 1 spike.
///
/// The state is deliberately small. iOS 26 drops an update whose encoded content state
/// exceeds 4 KB without raising an error, so `LiveActivityController` measures the
/// encoded size on every update rather than assuming it fits.
struct SpikeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var tick: Int
        var updatedAt: Date
        var startedAt: Date
        var mechanism: String

        /// Seconds since the last location fix, nil if none has arrived. This is the
        /// number that stops advancing in the Metro tunnel, which is the condition the
        /// whole spike exists to test.
        var fixAge: TimeInterval?

        /// Longest observed interval between consecutive ticks. Shown on the Lock
        /// Screen so the result is readable at the end of a commute without unlocking
        /// the phone or reading the log.
        var maxGap: TimeInterval

        var elapsed: TimeInterval { updatedAt.timeIntervalSince(startedAt) }
    }

    var sessionName: String
}

extension TimeInterval {
    var shortDuration: String {
        let total = Int(rounded())
        return total >= 60 ? "\(total / 60)m \(total % 60)s" : "\(total)s"
    }
}

extension SpikeAttributes.ContentState {
    /// The pass/fail threshold from the Phase 1 success criteria.
    static let gapBudget: TimeInterval = 15

    var isHealthy: Bool { maxGap <= Self.gapBudget }

    var fixDescription: String {
        guard let fixAge else { return "no fix" }
        return "fix \(fixAge.shortDuration) ago"
    }
}
