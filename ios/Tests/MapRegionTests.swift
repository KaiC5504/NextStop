import CoreLocation
import MapKit
import XCTest
@testable import NextStop

final class MapRegionTests: XCTestCase {
    private func journey() throws -> Journey {
        let dto = try JSONDecoder.tfnswDecoder.decode(TripDTO.self, from: Fixture.data("trip-sample"))
        return try XCTUnwrap(Journey.list(from: dto).first)
    }

    private func walkLeg(path: [CLLocationCoordinate2D]) -> Leg {
        Leg(
            id: "w", mode: .walk, route: nil, headsign: nil,
            originName: "A", destinationName: "B",
            plannedDeparture: nil, estimatedDeparture: nil,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: false, path: path, stops: [], durationSeconds: 60
        )
    }

    func testRegionContainsEveryPointOnTheRoute() throws {
        let journey = try journey()
        let region = try XCTUnwrap(MapFraming.region(for: journey))
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        for leg in journey.legs {
            for point in leg.path {
                XCTAssertTrue((minLat...maxLat).contains(point.latitude))
                XCTAssertTrue((minLon...maxLon).contains(point.longitude))
            }
        }
    }

    /// A journey between two stops a few hundred metres apart must not produce a span so
    /// small the map renders at maximum zoom on a blank tile.
    func testRegionHasAMinimumSpan() {
        let point = CLLocationCoordinate2D(latitude: -33.7969, longitude: 151.1804)
        let region = MapFraming.region(for: Journey(id: "j", legs: [walkLeg(path: [point, point])]))
        XCTAssertNotNil(region)
        XCTAssertGreaterThanOrEqual(region!.span.latitudeDelta, 0.005)
    }

    func testJourneyWithNoGeometryHasNoRegion() {
        XCTAssertNil(MapFraming.region(for: Journey(id: "j", legs: [walkLeg(path: [])])))
    }

    /// Transposing these two puts the launch screen off the coast of Morocco, and nothing
    /// else in the app would fail.
    func testTheDefaultRegionIsOverSydney() {
        XCTAssertEqual(MapFraming.sydney.center.latitude, -33.87, accuracy: 0.05)
        XCTAssertEqual(MapFraming.sydney.center.longitude, 151.21, accuracy: 0.05)
    }
}
