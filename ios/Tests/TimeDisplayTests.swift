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

    func testClockRangeCollapsesASharedMeridiem() {
        let from = Date(timeIntervalSince1970: 1_767_580_200) // 1:30 pm AEDT
        XCTAssertEqual(TimeDisplay.clockRange(from: from, to: from.addingTimeInterval(43 * 60)), "1:30 – 2:13 pm")
    }

    func testClockRangeKeepsDistinctMeridiems() {
        let to = Date(timeIntervalSince1970: 1_767_580_200).addingTimeInterval(-70 * 60) // 12:20 pm
        let from = to.addingTimeInterval(-22 * 60) // 11:58 am
        XCTAssertEqual(TimeDisplay.clockRange(from: from, to: to), "11:58 am – 12:20 pm")
    }

    func testLongDurationLabelBreaksAtAnHour() {
        XCTAssertEqual(TimeDisplay.longDurationLabel(seconds: 43 * 60), "43 min")
        XCTAssertEqual(TimeDisplay.longDurationLabel(seconds: 3_600), "1 hr")
        XCTAssertEqual(TimeDisplay.longDurationLabel(seconds: 75 * 60), "1 hr 15 min")
        XCTAssertNil(TimeDisplay.longDurationLabel(seconds: nil))
        XCTAssertNil(TimeDisplay.longDurationLabel(seconds: 0))
    }

    func testWalkBadgeMinutesRoundsAndHides() {
        XCTAssertEqual(TimeDisplay.walkBadgeMinutes(seconds: 290), "5")
        XCTAssertEqual(TimeDisplay.walkBadgeMinutes(seconds: 20), "1")
        XCTAssertNil(TimeDisplay.walkBadgeMinutes(seconds: nil))
        XCTAssertNil(TimeDisplay.walkBadgeMinutes(seconds: 0))
    }

    func testClockIsPinnedToSydney() {
        // 2026-01-05 02:30 UTC == 1:30 pm AEDT.
        let instant = Date(timeIntervalSince1970: 1_767_580_200)
        XCTAssertEqual(TimeDisplay.clock.string(from: instant), "1:30 pm")
    }

    func testRemainingLabelCountsDownToArrival() {
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(43 * 60), now: anchor), "43 min")
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(75 * 60), now: anchor), "1 hr 15 min")
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(20), now: anchor), "1 min")
    }

    func testRemainingLabelReadsArrivedOncePassed() {
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor, now: anchor), "Arrived")
        XCTAssertEqual(TimeDisplay.remainingLabel(until: anchor.addingTimeInterval(-300), now: anchor), "Arrived")
    }

    func testRemainingLabelHidesWithoutAnArrival() {
        XCTAssertNil(TimeDisplay.remainingLabel(until: nil, now: anchor))
    }
}
