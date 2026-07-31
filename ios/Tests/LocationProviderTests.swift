import CoreLocation
import XCTest
@testable import NextStop

@MainActor
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

    func testIngestedLocationPublishesCoordinateAndAccuracy() {
        let provider = LocationProvider()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -33.7969, longitude: 151.1804),
            altitude: 0, horizontalAccuracy: 12, verticalAccuracy: 5, timestamp: Date()
        )
        provider.ingest(location: location)
        XCTAssertEqual(provider.coordinate?.latitude, -33.7969)
        XCTAssertEqual(provider.horizontalAccuracy, 12)
    }

    /// Core Location marks an invalid fix with a negative accuracy rather than nil.
    /// Publishing that as a real number would draw a confidently precise dot on garbage.
    func testNegativeHorizontalAccuracyPublishesAsNil() {
        let provider = LocationProvider()
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -33.7969, longitude: 151.1804),
            altitude: 0, horizontalAccuracy: -1, verticalAccuracy: 5, timestamp: Date()
        )
        provider.ingest(location: location)
        XCTAssertNil(provider.horizontalAccuracy)
    }

    func testIngestedHeadingPublishes() {
        let provider = LocationProvider()
        provider.ingest(headingDegrees: 45, accuracy: 10)
        XCTAssertEqual(provider.headingDegrees, 45)
        XCTAssertEqual(provider.headingAccuracy, 10)
    }

    /// A negative heading accuracy means the compass reading is unusable. Clearing both
    /// values is what hides the cone — a stale direction is worse than none.
    func testInvalidHeadingClearsBothValues() {
        let provider = LocationProvider()
        provider.ingest(headingDegrees: 45, accuracy: 10)
        provider.ingest(headingDegrees: 300, accuracy: -1)
        XCTAssertNil(provider.headingDegrees)
        XCTAssertNil(provider.headingAccuracy)
    }

    func testFidelitySwitchesDesiredAccuracy() {
        let provider = LocationProvider()
        XCTAssertEqual(provider.desiredAccuracy, kCLLocationAccuracyHundredMeters)
        provider.set(fidelity: .navigation)
        XCTAssertEqual(provider.desiredAccuracy, kCLLocationAccuracyNearestTenMeters)
        provider.set(fidelity: .ambient)
        XCTAssertEqual(provider.desiredAccuracy, kCLLocationAccuracyHundredMeters)
    }
}
