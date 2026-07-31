import Foundation

struct AlightAlert: Equatable, Identifiable {
    /// "alight-" + the leg's id — stable across replans of the same leg, so
    /// UNUserNotificationCenter replaces instead of accumulating.
    let id: String
    let stopName: String
    let fireDate: Date
    let body: String
}

/// Plans the "time to get off" notifications: one per transit leg, shortly before its
/// estimated arrival. PROJECT_BRIEF §5.2 layer 1 — locally scheduled, so it fires with
/// the phone locked regardless of GPS, connectivity, or whether the app is still alive.
/// Pure; the scheduler owns UNUserNotificationCenter.
enum AlightAlertPlanner {
    /// Enough warning to gather up and get to the door, not so much it reads as an
    /// earlier stop.
    static let lead: TimeInterval = 150
    /// Joined inside the lead window, the alert falls back to this before arrival.
    /// Closer than this there is nothing useful left to say.
    static let minimumNotice: TimeInterval = 60

    static func alerts(for journey: Journey, now: Date) -> [AlightAlert] {
        journey.transitLegs.compactMap { leg in
            guard let arrival = leg.arrival else { return nil }
            let candidates = [
                arrival.addingTimeInterval(-lead),
                arrival.addingTimeInterval(-minimumNotice),
            ]
            guard let fireDate = candidates.first(where: { $0 > now }) else { return nil }
            return AlightAlert(
                id: "alight-\(leg.id)",
                stopName: leg.destinationName,
                fireDate: fireDate,
                body: "Get off at \(leg.destinationName) — arriving \(TimeDisplay.clock.string(from: arrival))"
            )
        }
    }

    /// What to change so the pending set matches `planned`. Unchanged alerts appear in
    /// neither list, so a 30-second replan with steady estimates schedules nothing. An
    /// alert whose fire time already passed is never re-added under the same id — the
    /// phone rang once; a moved estimate must not ring it twice.
    static func diff(
        planned: [AlightAlert], scheduled: [AlightAlert], now: Date
    ) -> (add: [AlightAlert], removeIDs: [String]) {
        let plannedIDs = Set(planned.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: scheduled.map { ($0.id, $0) })
        let add = planned.filter { plan in
            guard let existing = byID[plan.id] else { return true }
            guard existing != plan else { return false }
            return existing.fireDate > now
        }
        let removeIDs = scheduled.map(\.id).filter { !plannedIDs.contains($0) }
        return (add, removeIDs)
    }
}
