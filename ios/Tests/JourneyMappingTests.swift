import CoreLocation
import XCTest
@testable import NextStop

final class JourneyMappingTests: XCTestCase {
    private func journeys() throws -> [Journey] {
        let dto = try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
        return Journey.list(from: dto)
    }

    private func leg(planned: Date?, estimated: Date?, realtime: Bool) -> Leg {
        Leg(
            id: "test", mode: .bus, route: "412", headsign: "USyd",
            originName: "A", destinationName: "B",
            plannedDeparture: planned, estimatedDeparture: estimated,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: realtime, path: [], stops: [], durationSeconds: 600
        )
    }

    func testJourneysAreBuiltWithLegs() throws {
        let all = try journeys()
        XCTAssertFalse(all.isEmpty)
        XCTAssertFalse(all[0].legs.isEmpty)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "journey ids must be unique")
    }

    /// Decoding the same payload twice must produce the same ids. The live screen re-plans
    /// every 30s; unstable ids make SwiftUI rebuild every row and lose which legs the user
    /// has already rated.
    func testIdsAreStableAcrossDecodes() throws {
        XCTAssertEqual(try journeys().map(\.id), try journeys().map(\.id))
        XCTAssertEqual(try journeys()[0].legs.map(\.id), try journeys()[0].legs.map(\.id))
    }

    /// The Metro sends the whole line name in `number` and the short code in
    /// `disassembledName`. A badge showing "M1 Metro North West & Bankstown Line" is the
    /// failure this catches.
    func testRouteUsesTheShortName() throws {
        let routes = try journeys()[0].transitLegs.compactMap(\.route)
        XCTAssertFalse(routes.isEmpty)
        for route in routes {
            XCTAssertLessThanOrEqual(route.count, 8, "\(route) is too long for a route badge")
        }
    }

    func testPathIsConvertedToCoordinates() throws {
        let transit = try XCTUnwrap(journeys().first?.transitLegs.first)
        XCTAssertGreaterThan(transit.path.count, 2)
        XCTAssertTrue((-45...(-25)).contains(transit.path[0].latitude))
    }

    func testDepartureFallsBackToPlannedWhenNoEstimate() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let subject = leg(planned: planned, estimated: nil, realtime: false)
        XCTAssertEqual(subject.departure, planned)
        XCTAssertNil(subject.delaySeconds)
    }

    func testDelayIsTheDifferenceBetweenEstimateAndPlan() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let subject = leg(planned: planned, estimated: planned.addingTimeInterval(180), realtime: true)
        XCTAssertEqual(subject.delaySeconds, 180)
        XCTAssertEqual(subject.departure, planned.addingTimeInterval(180))
    }

    func testJourneySpansFirstDepartureToLastArrival() throws {
        let journey = try XCTUnwrap(journeys().first)
        let departure = try XCTUnwrap(journey.departure)
        let arrival = try XCTUnwrap(journey.arrival)
        XCTAssertGreaterThan(arrival, departure)
    }

    func testWalkingLegsAreExcludedFromTransitLegs() throws {
        for journey in try journeys() {
            XCTAssertFalse(journey.transitLegs.contains { $0.mode.isWalking })
        }
    }
}
