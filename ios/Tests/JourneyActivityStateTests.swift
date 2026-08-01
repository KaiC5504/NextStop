import CoreLocation
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
        realtime: Bool = false, stops: [LegStop] = []
    ) -> Leg {
        Leg(
            id: id, mode: mode, route: route, headsign: headsign,
            originName: origin, destinationName: destination,
            plannedDeparture: plannedDeparture.map(base.addingTimeInterval),
            estimatedDeparture: estimatedDeparture.map(base.addingTimeInterval),
            plannedArrival: plannedArrival.map(base.addingTimeInterval),
            estimatedArrival: estimatedArrival.map(base.addingTimeInterval),
            hasRealtime: realtime, path: [], stops: stops, durationSeconds: nil
        )
    }

    private func stop(_ name: String, arrival: TimeInterval?, departure: TimeInterval? = nil) -> LegStop {
        LegStop(
            id: name, name: name,
            coordinate: CLLocationCoordinate2D(latitude: -33.8, longitude: 151.2),
            departure: departure.map(base.addingTimeInterval),
            arrival: arrival.map(base.addingTimeInterval)
        )
    }

    private var trainStops: [LegStop] {
        [
            stop("Chatswood", arrival: nil, departure: 780),
            stop("Artarmon", arrival: 1_000),
            stop("St Leonards", arrival: 1_240),
            stop("Wollstonecraft", arrival: 1_500),
            stop("North Sydney", arrival: 1_800),
            stop("Wynyard", arrival: 2_100),
            stop("Central", arrival: 2_400),
        ]
    }

    private func journey(trainEstimate: TimeInterval? = 780) -> Journey {
        let legs = [
            leg(id: "walk1", mode: .walk, origin: "Home", destination: "Chatswood Station",
                plannedDeparture: 0, plannedArrival: 300),
            leg(id: "train", mode: .train, route: "T1", headsign: "Central via Gordon",
                origin: "Chatswood Station", destination: "Central",
                plannedDeparture: 600, estimatedDeparture: trainEstimate,
                plannedArrival: 2400, realtime: true, stops: trainStops),
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
        for offset: TimeInterval in [100, 400, 1_000, 1_100, 2_000, 4_000] {
            XCTAssertEqual(derive(at: offset), derive(at: offset + 1), "unstable at offset \(offset)")
        }
    }

    func testRidingCarriesStationProgress() throws {
        let state = try XCTUnwrap(derive(at: 1_100))
        XCTAssertEqual(state.stopIndex, 2, "Chatswood and Artarmon are behind us")
        XCTAssertEqual(state.stopCount, 7)
        XCTAssertEqual(state.nextStopName, "St Leonards")
        // Intermediate arrivals mapped into the 780...2400 countdown, 3-dp quantized.
        XCTAssertEqual(state.stopFractions, [0.136, 0.284, 0.444, 0.63, 0.815])
    }

    /// Crossing a stop time may move only the discrete station facts — the anchors and
    /// fractions the bar animates over must hold still or every crossing redraws it.
    func testPassingAStopChangesOnlyTheStationFields() throws {
        let before = try XCTUnwrap(derive(at: 1_239))
        let after = try XCTUnwrap(derive(at: 1_241))
        XCTAssertEqual(before.stopIndex, 2)
        XCTAssertEqual(after.stopIndex, 3)
        XCTAssertEqual(before.nextStopName, "St Leonards")
        XCTAssertEqual(after.nextStopName, "Wollstonecraft")
        XCTAssertEqual(before.stopFractions, after.stopFractions)
        XCTAssertEqual(before.countdownStart, after.countdownStart)
        XCTAssertEqual(before.countdownEnd, after.countdownEnd)
    }

    func testStationFieldsAreNilOffTheRidingPhase() throws {
        for offset: TimeInterval in [100, 400, 4_000] {
            let state = try XCTUnwrap(derive(at: offset))
            XCTAssertNil(state.stopIndex, "at offset \(offset)")
            XCTAssertNil(state.stopCount, "at offset \(offset)")
            XCTAssertNil(state.nextStopName, "at offset \(offset)")
            XCTAssertNil(state.stopFractions, "at offset \(offset)")
        }
    }

    /// Real stop names carry boarding suffixes; the Lock Screen caption should not.
    func testNextStopNameIsCleaned() throws {
        var legs = journey().legs
        let suffixed = [
            stop("Chatswood Station, Platform 2", arrival: nil, departure: 780),
            stop("Artarmon Station, Platform 2", arrival: 1_000),
            stop("St Leonards Station, Platform 1", arrival: 1_240),
            stop("Central Station, Platform 16", arrival: 2_400),
        ]
        legs[1] = leg(id: "train", mode: .train, route: "T1",
                      origin: "Chatswood Station", destination: "Central",
                      plannedDeparture: 600, estimatedDeparture: 780,
                      plannedArrival: 2_400, realtime: true, stops: suffixed)
        let state = try XCTUnwrap(derive(at: 1_100, journey: Journey(id: "test", legs: legs)))
        XCTAssertEqual(state.nextStopName, "St Leonards Station")
    }

    func testRidingWithoutAStopSequenceDerivesNilProgress() throws {
        var legs = journey().legs
        legs[1] = leg(id: "train", mode: .train, route: "T1",
                      origin: "Chatswood Station", destination: "Central",
                      plannedDeparture: 600, estimatedDeparture: 780,
                      plannedArrival: 2_400, realtime: true)
        let state = try XCTUnwrap(derive(at: 1_000, journey: Journey(id: "test", legs: legs)))
        XCTAssertEqual(state.phase, .riding)
        XCTAssertNil(state.stopIndex)
        XCTAssertNil(state.stopCount)
        XCTAssertNil(state.stopFractions)
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
            nextLegLine: "Then \(longName) · 12:59 pm",
            stopIndex: 47, stopCount: 48,
            nextStopName: longName,
            // The 46-intermediate cap: the longest stop sequence the payload will carry.
            stopFractions: (1...46).map { (Double($0) / 47 * 1_000).rounded() / 1_000 }
        )
        let encoded = try JSONEncoder().encode(state)
        XCTAssertLessThan(encoded.count, 3_500)
        XCTAssertEqual(
            try JSONDecoder().decode(JourneyActivityAttributes.ContentState.self, from: encoded),
            state
        )
    }
}
