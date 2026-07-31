import XCTest
@testable import NextStop

final class ActivityHeartbeatTests: XCTestCase {
    private let anchor = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testNeverSentMeansSend() {
        XCTAssertTrue(ActivityHeartbeat.shouldResend(lastSentAt: nil, now: anchor, staleAfter: 180))
    }

    func testResendsOnlyPastHalfTheStaleWindow() {
        XCTAssertFalse(ActivityHeartbeat.shouldResend(
            lastSentAt: anchor, now: anchor.addingTimeInterval(89), staleAfter: 180
        ))
        XCTAssertFalse(ActivityHeartbeat.shouldResend(
            lastSentAt: anchor, now: anchor.addingTimeInterval(90), staleAfter: 180
        ))
        XCTAssertTrue(ActivityHeartbeat.shouldResend(
            lastSentAt: anchor, now: anchor.addingTimeInterval(91), staleAfter: 180
        ))
    }
}
