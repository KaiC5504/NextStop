import XCTest
@testable import NextStop

final class JourneyActivityStateTests: XCTestCase {
    /// Seconds offsets from `base` for a Chatswood → USyd shape: walk to the station,
    /// train running 3 minutes late, walk to the destination.
    private let base = Date(timeIntervalSince1970: 1_753_900_000)

    private func leg(
        id: String, mode: TransitMode, route: String? = nil, headsign: String? = nil,
        origin: String, destination: String,
        plannedDeparture: TimeInterval?, estimatedDeparture: TimeInterval? = nil,
        plannedArrival: TimeInterval?, estimatedArrival: TimeInterval? = nil,
        realtime: Bool = false
    ) -> Leg {
        Leg(
            id: id, mode: mode, route: route, headsign: headsign,
            originName: origin, destinationName: destination,
            plannedDeparture: plannedDeparture.map(base.addingTimeInterval),
            estimatedDeparture: estimatedDeparture.map(base.addingTimeInterval),
            plannedArrival: plannedArrival.map(base.addingTimeInterval),
            estimatedArrival: estimatedArrival.map(base.addingTimeInterval),
            hasRealtime: realtime, path: [], stops: [], durationSeconds: nil
        )
    }

    private func journey(trainEstimate: TimeInterval? = 780) -> Journey {
        let legs = [
            leg(id: "walk1", mode: .walk, origin: "Home", destination: "Chatswood Station",
                plannedDeparture: 0, plannedArrival: 300),
            leg(id: "train", mode: .train, route: "T1", headsign: "Central via Gordon",
                origin: "Chatswood Station", destination: "Central",
                plannedDeparture: 600, estimatedDeparture: trainEstimate,
                plannedArrival: 2400, realtime: true),
            leg(id: "walk2", mode: .walk, origin: "Central", destination: "USyd City Rd",
                plannedDeparture: 2500, plannedArrival: 3400),
        ]
        return Journey(id: "test", legs: legs)
    }

    private func derive(at offset: TimeInterval, journey: Journey? = nil) -> JourneyActivityAttributes.ContentState? {
        JourneyActivityState.make(
            journey: journey ?? self.journey(),
            destinationName: "University of Sydney",
            startedAt: base,
            now: base.addingTimeInterval(offset)
        )
    }

    func testWalkingLegBorrowsTheConnectionStatus() throws {
        let state = try XCTUnwrap(derive(at: 100))
        XCTAssertEqual(state.phase, .walking)
        XCTAssertEqual(state.mode, .walk)
        XCTAssertEqual(state.place, "Chatswood Station")
        XCTAssertNil(state.routeBadge)
        // Train estimated 780 vs planned 600 = 3 min late — visible while still walking.
        XCTAssertEqual(state.status, .late(3))
        let expectedClock = JourneyActivityState.clock.string(from: base.addingTimeInterval(780))
        XCTAssertEqual(state.nextLegLine, "Then T1 · \(expectedClock)")
        XCTAssertEqual(state.legIndex, 1)
        XCTAssertEqual(state.legCount, 3)
    }

    func testWaitingCountsDownToTheEstimatedDeparture() throws {
        let state = try XCTUnwrap(derive(at: 400))
        XCTAssertEqual(state.phase, .waiting)
        XCTAssertEqual(state.place, "Chatswood Station")
        XCTAssertEqual(state.routeBadge, "T1")
        XCTAssertEqual(state.countdownEnd, base.addingTimeInterval(780))
        XCTAssertEqual(state.status, .late(3))
        XCTAssertEqual(state.legIndex, 2)
    }

    func testRidingCountsDownToAlighting() throws {
        let state = try XCTUnwrap(derive(at: 1_000))
        XCTAssertEqual(state.phase, .riding)
        XCTAssertEqual(state.place, "Central")
        XCTAssertEqual(state.countdownStart, base.addingTimeInterval(780))
        XCTAssertEqual(state.countdownEnd, base.addingTimeInterval(2_400))
        XCTAssertNil(state.nextLegLine)
    }

    func testArrivedAfterTheFinalLeg() throws {
        let state = try XCTUnwrap(derive(at: 4_000))
        XCTAssertEqual(state.phase, .arrived)
        XCTAssertEqual(state.place, "University of Sydney")
        XCTAssertEqual(state.legIndex, 3)
        XCTAssertEqual(state.legCount, 3)
    }

    /// The controller sends an update only when the derived state changes, so a tick
    /// with no new facts must derive an identical value. A now-based field sneaking
    /// into the schema is exactly what this catches.
    func testDerivationIsStableAcrossASecond() {
        for offset: TimeInterval in [100, 400, 1_000, 4_000] {
            XCTAssertEqual(derive(at: offset), derive(at: offset + 1), "unstable at offset \(offset)")
        }
    }

    func testReplanMovesTheCountdownTarget() throws {
        let before = try XCTUnwrap(derive(at: 400))
        let after = try XCTUnwrap(derive(at: 400, journey: journey(trainEstimate: 900)))
        XCTAssertEqual(after.countdownEnd, base.addingTimeInterval(900))
        XCTAssertNotEqual(before, after)
    }

    func testCountdownRangeIsAlwaysOrdered() throws {
        for offset: TimeInterval in [50, 100, 400, 1_000, 2_450, 2_600, 4_000] {
            let state = try XCTUnwrap(derive(at: offset))
            XCTAssertLessThanOrEqual(state.countdownStart, state.countdownEnd, "inverted at offset \(offset)")
        }
    }

    func testNoRealtimeDerivesScheduledOnly() throws {
        var legs = journey().legs
        legs[1] = leg(id: "train", mode: .train, route: "T1",
                      origin: "Chatswood Station", destination: "Central",
                      plannedDeparture: 600, plannedArrival: 2_400, realtime: false)
        let state = try XCTUnwrap(derive(at: 400, journey: Journey(id: "test", legs: legs)))
        XCTAssertEqual(state.status, .scheduledOnly)
    }

    func testEmptyJourneyDerivesNothing() {
        XCTAssertNil(derive(at: 0, journey: Journey(id: "empty", legs: [])))
    }

    /// iOS 26 drops content states over 4 KB without an error; the controller guards at
    /// 3 500 encoded bytes. Long Sydney interchange names should not get near it.
    func testWorstCasePayloadStaysUnderTheGuard() throws {
        let longName = String(repeating: "Macquarie Fields Interchange ", count: 3)
        let state = JourneyActivityAttributes.ContentState(
            phase: .waiting, mode: .schoolBus, routeBadge: "601X-Express",
            headsign: longName, place: longName,
            countdownStart: Date(timeIntervalSince1970: 1_800_000_000),
            countdownEnd: Date(timeIntervalSince1970: 1_800_003_600),
            status: .late(12), arrivalShort: "12:59 pm",
            legIndex: 8, legCount: 12,
            nextLegLine: "Then \(longName) · 12:59 pm"
        )
        let encoded = try JSONEncoder().encode(state)
        XCTAssertLessThan(encoded.count, 3_500)
        XCTAssertEqual(
            try JSONDecoder().decode(JourneyActivityAttributes.ContentState.self, from: encoded),
            state
        )
    }
}
