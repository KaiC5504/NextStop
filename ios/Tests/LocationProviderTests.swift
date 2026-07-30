import CoreLocation
import XCTest
@testable import NextStop

final class LocationProviderTests: XCTestCase {
    /// The Trip Planner takes a coordinate origin as "longitude:latitude:EPSG:4326" —
    /// longitude first, the opposite order to everything else in this codebase.
    func testCoordinateOriginIsLongitudeFirst() {
        let coordinate = CLLocationCoordinate2D(latitude: -33.7969, longitude: 151.1804)
        XCTAssertEqual(
            LocationProvider.tfnswOriginString(for: coordinate),
            "151.180400:-33.796900:EPSG:4326"
        )
    }
}
