import ActivityKit
import UIKit
import UserNotifications

/// Exists for exactly one callback. With the journey-scoped background location hold
/// the app is running — not suspended — when the user force-quits mid-journey, so
/// willTerminate fires and the Live Activity and pending hop-off alerts die with the
/// app instead of narrating a journey nobody is on. Best-effort by design: jetsam and
/// crashes get no callback, which is why the launch sweeps stay.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        // CI terminates the app between screenshot launches and the test scheme passes
        // -initialScreen too; those runs have nothing real to tear down.
        guard UserDefaults.standard.string(forKey: "initialScreen") == nil else { return }
        // The app schedules nothing but "alight-" requests, so removeAll is exact.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        // ActivityKit has no synchronous end. The detached task touches no main-actor
        // state, so blocking the main thread here cannot deadlock it; the 2s cap stays
        // far inside the termination allowance.
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            for activity in Activity<JourneyActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }
}
