import XCTest
@testable import NextStop

final class PlanTimeTests: XCTestCase {
    // 2026-01-05 02:30 UTC == 1:30 pm AEDT.
    private let instant = Date(timeIntervalSince1970: 1_767_580_200)

    func testMacrosMatchEFA() {
        XCTAssertEqual(PlanTime.depart(instant).macro, "dep")
        XCTAssertEqual(PlanTime.arrive(instant).macro, "arr")
        XCTAssertEqual(PlanTime.arrive(instant).date, instant)
    }

    func testLeaveNowResolvesToDepartingAtNow() {
        XCTAssertEqual(PlanTimeSelection.leaveNow.resolved(now: instant), .depart(instant))
        XCTAssertEqual(PlanTimeSelection.departAt(instant).resolved(now: .distantPast), .depart(instant))
        XCTAssertEqual(PlanTimeSelection.arriveBy(instant).resolved(now: .distantPast), .arrive(instant))
    }

    func testLabelsAreSydneyClocks() {
        XCTAssertEqual(PlanTimeSelection.leaveNow.label, "Leave now")
        XCTAssertEqual(PlanTimeSelection.departAt(instant).label, "Depart 1:30 pm")
        XCTAssertEqual(PlanTimeSelection.arriveBy(instant).label, "Arrive by 1:30 pm")
    }
}
