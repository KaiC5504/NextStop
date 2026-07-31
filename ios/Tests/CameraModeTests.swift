import XCTest
@testable import NextStop

final class CameraModeTests: XCTestCase {
    private let all: [CameraMode] = [.free, .centered, .following]

    /// The Google Maps cycle: centre first, face-forward second, and a third tap drops
    /// back to centred rather than to free — leaving follow should feel like stepping
    /// down, not like losing your place.
    func testRecenterCyclesThroughTheStages() {
        XCTAssertEqual(CameraMode.free.reduced(.recenterTapped), .centered)
        XCTAssertEqual(CameraMode.centered.reduced(.recenterTapped), .following)
        XCTAssertEqual(CameraMode.following.reduced(.recenterTapped), .centered)
    }

    func testAnyPanReturnsToFree() {
        for mode in all {
            XCTAssertEqual(mode.reduced(.userPanned), .free)
        }
    }

    /// Selecting a journey frames the whole route; staying in follow would immediately
    /// yank the camera back to the user and undo the framing.
    func testJourneyFramingReturnsToFree() {
        for mode in all {
            XCTAssertEqual(mode.reduced(.journeyFramed), .free)
        }
    }

    func testLosingTheFixReturnsToFree() {
        for mode in all {
            XCTAssertEqual(mode.reduced(.locationUnavailable), .free)
        }
    }
}
