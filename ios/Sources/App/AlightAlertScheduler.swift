import Foundation
import UserNotifications

/// The seam between the pure planner and UNUserNotificationCenter, so tests never touch
/// the real center — a permission dialog on the CI simulator would park over every
/// screenshot taken after it.
protocol NotificationScheduling {
    func requestAuthorization() async -> Bool
    func add(_ alert: AlightAlert) async
    func removePending(ids: [String])
    func pendingAlertIDs() async -> [String]
}

/// Applies the planner's diffs to the notification center and remembers what it armed.
@MainActor
final class AlightAlertScheduler {
    private let center: NotificationScheduling
    private var scheduled: [AlightAlert] = []
    private var authorized: Bool?

    init(center: NotificationScheduling = UserNotificationScheduler()) {
        self.center = center
    }

    /// First call asks for permission (this is the journey-commitment moment, the one
    /// place a prompt reads as expected) and sweeps orphans a force-quit left pending.
    func begin(journey: Journey?, now: Date) async {
        if authorized == nil {
            authorized = await center.requestAuthorization()
            let orphans = await center.pendingAlertIDs().filter { pending in
                !scheduled.contains { $0.id == pending }
            }
            if !orphans.isEmpty { center.removePending(ids: orphans) }
        }
        await sync(journey: journey, now: now)
    }

    func sync(journey: Journey?, now: Date) async {
        guard authorized == true else { return }
        let planned = journey.map { AlightAlertPlanner.alerts(for: $0, now: now) } ?? []
        let (add, removeIDs) = AlightAlertPlanner.diff(planned: planned, scheduled: scheduled, now: now)
        if !removeIDs.isEmpty {
            center.removePending(ids: removeIDs)
            scheduled.removeAll { removeIDs.contains($0.id) }
        }
        for alert in add {
            await center.add(alert)
            scheduled.removeAll { $0.id == alert.id }
            scheduled.append(alert)
        }
    }

    func cancelAll() {
        let ids = scheduled.map(\.id)
        if !ids.isEmpty { center.removePending(ids: ids) }
        scheduled = []
    }
}

final class UserNotificationScheduler: NotificationScheduling {
    /// Also keeps alerts visible when they land with the app foreground — without a
    /// delegate, willPresent defaults to suppressing them.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }

    private let presenter = Presenter()

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func add(_ alert: AlightAlert) async {
        let content = UNMutableNotificationContent()
        content.title = "Time to get off"
        content.body = alert.body
        content.sound = .default
        let interval = alert.fireDate.timeIntervalSinceNow
        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    func removePending(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func pendingAlertIDs() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("alight-") }
    }
}
