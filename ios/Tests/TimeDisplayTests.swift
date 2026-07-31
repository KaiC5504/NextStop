import XCTest
@testable import NextStop

final class TimeDisplayTests: XCTestCase {
    private let anchor = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testDurationRoundsToNearestMinute() {
        XCTAssertEqual(TimeDisplay.durationLabel(seconds: 540), "9 min")
        XCTAssertEqual(TimeDisplay.durationLabel(seconds: 559), "9 min")
        XCTAssertEqual(TimeDisplay.durationLabel(seconds: 570), "10 min")
    }

    func testMissingOrDegenerateDurationHidesTheLabel() {
        XCTAssertNil(TimeDisplay.durationLabel(seconds: nil))
        XCTAssertNil(TimeDisplay.durationLabel(seconds: 0))
        XCTAssertNil(TimeDisplay.durationLabel(seconds: -30))
    }

    func testTinyDurationClampsToOneMinute() {
        XCTAssertEqual(TimeDisplay.durationLabel(seconds: 20), "1 min")
    }

    func testCountdownLabelsAndWindows() {
        XCTAssertNil(TimeDisplay.countdownLabel(to: nil, now: anchor))
        XCTAssertNil(TimeDisplay.countdownLabel(to: anchor.addingTimeInterval(-61), now: anchor))
        XCTAssertEqual(TimeDisplay.countdownLabel(to: anchor.addingTimeInterval(-60), now: anchor), "now")
        XCTAssertEqual(TimeDisplay.countdownLabel(to: anchor.addingTimeInterval(25), now: anchor), "now")
        XCTAssertEqual(TimeDisplay.countdownLabel(to: anchor.addingTimeInterval(14.4 * 60), now: anchor), "in 14 min")
        XCTAssertEqual(TimeDisplay.countdownLabel(to: anchor.addingTimeInterval(14.6 * 60), now: anchor), "in 15 min")
    }

    func testClockIsPinnedToSydney() {
        // 2026-01-05 02:30 UTC == 1:30 pm AEDT.
        let instant = Date(timeIntervalSince1970: 1_767_580_200)
        XCTAssertEqual(TimeDisplay.clock.string(from: instant), "1:30 pm")
    }
}
