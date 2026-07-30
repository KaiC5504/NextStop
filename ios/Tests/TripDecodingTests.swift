import XCTest
@testable import NextStop

final class TripDecodingTests: XCTestCase {
    private func decoded() throws -> TripDTO {
        try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
    }

    func testJourneysAndLegsDecode() throws {
        let journeys = try XCTUnwrap(decoded().journeys)
        XCTAssertFalse(journeys.isEmpty)
        XCTAssertFalse(try XCTUnwrap(journeys[0].legs).isEmpty)
    }

    /// `coords` is what makes a real map possible. A leg drawn as a straight line between
    /// two stops is the failure this test exists to catch.
    func testTransitLegsCarryRouteGeometry() throws {
        let legs = try XCTUnwrap(decoded().journeys?.first?.legs)
        let transit = legs.filter { !TransitMode(productClass: $0.transportation?.product?.productClass).isWalking }
        XCTAssertFalse(transit.isEmpty, "fixture has no transit leg")
        for leg in transit {
            XCTAssertGreaterThan(leg.coords?.count ?? 0, 2)
            let first = try XCTUnwrap(leg.coords?.first)
            XCTAssertEqual(first.count, 2)
            XCTAssertTrue((-45...(-25)).contains(first[0]), "latitude \(first[0]) is not in NSW")
            XCTAssertTrue((140...155).contains(first[1]), "longitude \(first[1]) is not in NSW")
        }
    }

    func testTimesDecodeAsDates() throws {
        let leg = try XCTUnwrap(decoded().journeys?.first?.legs?.first)
        XCTAssertNotNil(leg.origin?.departureTimePlanned)
        XCTAssertNotNil(leg.destination?.arrivalTimePlanned)
    }

    func testProductClassDecodesFromReservedKeyword() throws {
        let legs = try XCTUnwrap(decoded().journeys?.first?.legs)
        XCTAssertTrue(legs.contains { $0.transportation?.product?.productClass != nil })
    }

    func testStopSequenceCarriesNamedCoordinates() throws {
        let legs = try XCTUnwrap(decoded().journeys?.first?.legs)
        let withStops = try XCTUnwrap(legs.first { ($0.stopSequence?.count ?? 0) > 1 })
        let stop = try XCTUnwrap(withStops.stopSequence?.first)
        XCTAssertEqual(stop.coord?.count, 2)
        XCTAssertNotNil(stop.name ?? stop.disassembledName)
    }
}
