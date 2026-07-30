import XCTest
@testable import NextStop

final class DepartureStatusTests: XCTestCase {
    private func leg(planned: Date?, estimated: Date?, realtime: Bool) -> Leg {
        Leg(
            id: "test", mode: .bus, route: "412", headsign: "USyd",
            originName: "A", destinationName: "B",
            plannedDeparture: planned, estimatedDeparture: estimated,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: realtime, path: [], stops: [], durationSeconds: 600
        )
    }

    /// Untracked is not the same as on time. Claiming a service is punctual when nobody is
    /// watching it is the exact dishonesty this app exists to avoid.
    func testNoRealtimeIsScheduledOnlyRatherThanOnTime() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: nil, realtime: false))
        XCTAssertEqual(status, .scheduledOnly)
        XCTAssertEqual(status.tint, Theme.Colors.noRealtime)
    }

    func testRealtimeFlagFalseIsScheduledOnlyEvenWithAnEstimate() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(300), realtime: false))
        XCTAssertEqual(status, .scheduledOnly)
    }

    func testWithinAMinuteCountsAsOnTime() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(30), realtime: true)), .onTime)
    }

    func testLateIsReportedInWholeMinutes() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(185), realtime: true))
        XCTAssertEqual(status, .late(3))
        XCTAssertEqual(status.label, "3 min late")
    }

    /// The same magnitude as the late case, negated, so this measures that early is its own
    /// state rather than the rounding convention. 150s would have been exactly 2.5 minutes,
    /// where the answer depends on which way `rounded()` breaks a tie.
    func testEarlyIsReportedSeparately() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let status = DepartureStatus(leg: leg(planned: base, estimated: base.addingTimeInterval(-185), realtime: true))
        XCTAssertEqual(status, .early(3))
        XCTAssertEqual(status.label, "3 min early")
    }
}
