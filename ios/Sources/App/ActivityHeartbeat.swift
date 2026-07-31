import Foundation

/// The controller skips ActivityKit when the derived state hasn't changed, but staleDate
/// only moves on an actual send — so a leg whose facts hold still for longer than the
/// stale window would grey to "May be out of date" while the app is foreground and
/// syncing every second. Resending the unchanged state at half the stale window keeps
/// staleDate sliding ahead of the deadline it exists to enforce.
enum ActivityHeartbeat {
    static func shouldResend(lastSentAt: Date?, now: Date, staleAfter: TimeInterval) -> Bool {
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) > staleAfter / 2
    }
}
