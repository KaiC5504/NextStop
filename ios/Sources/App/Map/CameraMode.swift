import Foundation

/// The map camera's intent, reduced Google Maps-style: first recenter tap centres on the
/// user north-up, the second rotates the map to face where the phone faces, and any
/// user pan or journey framing drops back to free.
///
/// A pure reducer because the actual `MapCameraPosition` writes are unverifiable without
/// a device — the transition table, at least, can be pinned by tests.
enum CameraMode: Equatable {
    case free, centered, following

    enum Event {
        case recenterTapped, userPanned, journeyFramed, locationUnavailable
    }

    func reduced(_ event: Event) -> CameraMode {
        switch (self, event) {
        case (.free, .recenterTapped): .centered
        case (.centered, .recenterTapped): .following
        case (.following, .recenterTapped): .centered
        case (_, .userPanned), (_, .journeyFramed), (_, .locationUnavailable): .free
        }
    }
}
