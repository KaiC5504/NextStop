import Foundation

extension DepartureStatus {
    /// A minute of slack either way. TfNSW estimates jitter by seconds constantly, and a
    /// "1 min late" that flips back a moment later reads as a broken app.
    private static let tolerance: TimeInterval = 60

    init(leg: Leg) {
        guard leg.hasRealtime, let delay = leg.delaySeconds else {
            self = .scheduledOnly
            return
        }
        let seconds = Double(delay)
        if abs(seconds) <= Self.tolerance {
            self = .onTime
        } else if seconds > 0 {
            self = .late(Int((seconds / 60).rounded()))
        } else {
            self = .early(Int((-seconds / 60).rounded()))
        }
    }
}
