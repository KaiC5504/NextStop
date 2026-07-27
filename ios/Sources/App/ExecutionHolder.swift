import CoreLocation
import Foundation

/// The mechanisms under test: ways of persuading iOS to keep the process running while
/// the phone is locked.
///
/// `none` is not filler. Without a control run you cannot tell whether a mechanism kept
/// the app alive or whether iOS simply had not got around to suspending it yet.
enum HoldMechanism: String, CaseIterable, Identifiable, Codable {
    case backgroundActivitySession
    case locationUpdates
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backgroundActivitySession: return "CLBackgroundActivitySession"
        case .locationUpdates: return "CLLocationManager updates"
        case .none: return "No holder (control)"
        }
    }

    var detail: String {
        switch self {
        case .backgroundActivitySession:
            return "Modern API. Works with When In Use and shows the system indicator."
        case .locationUpdates:
            return "Classic navigation-app approach: allowsBackgroundLocationUpdates."
        case .none:
            return "Expected to freeze once locked. Establishes the baseline."
        }
    }
}

protocol ExecutionHolder: AnyObject {
    func start()
    func stop()
    /// When the most recent location fix arrived, or nil if none has. Goes stale
    /// underground even while the hold itself may still be working.
    var lastFix: Date? { get }
}

/// iOS 17+ background activity session, paired with the async live-updates stream.
final class SessionHolder: NSObject, ExecutionHolder {
    private var session: CLBackgroundActivitySession?
    private var task: Task<Void, Never>?
    private(set) var lastFix: Date?

    func start() {
        session = CLBackgroundActivitySession()
        SpikeLog.shared.write("hold.start", "CLBackgroundActivitySession")

        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    if update.location != nil {
                        self.lastFix = Date()
                    }
                    // Logged because a stationary determination is a common precursor to
                    // the process being suspended, and there is no way to observe it
                    // live on a device with no debugger attached.
                    if update.isStationary {
                        SpikeLog.shared.write("location.stationary", "")
                    }
                }
            } catch {
                SpikeLog.shared.write("location.error", "\(error)")
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.invalidate()
        session = nil
        SpikeLog.shared.write("hold.stop", "CLBackgroundActivitySession")
    }
}

/// The long-standing navigation-app approach.
final class LocationUpdatesHolder: NSObject, ExecutionHolder, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastFix: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Without this iOS pauses updates when it decides you have stopped moving, and a
        // paused stream is exactly how the process ends up suspended mid-commute.
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .otherNavigation
    }

    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        SpikeLog.shared.write("hold.start", "CLLocationManager")
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        SpikeLog.shared.write("hold.stop", "CLLocationManager")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastFix = Date()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        SpikeLog.shared.write("location.error", "\(error.localizedDescription)")
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        SpikeLog.shared.write("location.paused", "system paused updates")
    }
}

final class NoHolder: ExecutionHolder {
    let lastFix: Date? = nil
    func start() { SpikeLog.shared.write("hold.start", "none (control)") }
    func stop() { SpikeLog.shared.write("hold.stop", "none (control)") }
}

enum HolderFactory {
    static func make(_ mechanism: HoldMechanism) -> ExecutionHolder {
        switch mechanism {
        case .backgroundActivitySession: return SessionHolder()
        case .locationUpdates: return LocationUpdatesHolder()
        case .none: return NoHolder()
        }
    }

    /// Both real mechanisms need authorization before they will do anything, and a
    /// denied prompt is otherwise indistinguishable from a mechanism that does not work.
    static func requestAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            SpikeLog.shared.write("auth.denied", "location permission refused")
        default:
            break
        }
    }
}
