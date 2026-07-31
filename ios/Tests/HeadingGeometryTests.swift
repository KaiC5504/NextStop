import XCTest
@testable import NextStop

final class HeadingGeometryTests: XCTestCase {
    func testScreenRotationAtNorthUpIsTheDeviceHeading() {
        XCTAssertEqual(HeadingGeometry.screenRotation(deviceHeading: 45, cameraHeading: 0), 45)
    }

    /// The rotated-camera cases are the point of this file: a flipped sign renders
    /// correctly at north-up — all the simulator ever shows — and wrong on the street.
    func testScreenRotationSubtractsTheCameraRotation() {
        XCTAssertEqual(HeadingGeometry.screenRotation(deviceHeading: 10, cameraHeading: 30), 340)
        XCTAssertEqual(HeadingGeometry.screenRotation(deviceHeading: 30, cameraHeading: 10), 20)
        // Heading-up follow: camera matches device, cone points straight up.
        XCTAssertEqual(HeadingGeometry.screenRotation(deviceHeading: 217, cameraHeading: 217), 0)
    }

    func testScreenRotationNormalisesWraparound() {
        XCTAssertEqual(HeadingGeometry.screenRotation(deviceHeading: 350, cameraHeading: -20), 10)
    }

    func testContinuousRotationTakesTheShortWayAcrossNorth() {
        XCTAssertEqual(HeadingGeometry.continuousRotation(from: 350, to: 10), 370)
        XCTAssertEqual(HeadingGeometry.continuousRotation(from: 10, to: 350), -10)
    }

    func testContinuousRotationStaysNearAnUnwoundAccumulator() {
        // The accumulator can sit far outside 0–360 after minutes of turning; the next
        // target must land beside it, not snap back into range.
        XCTAssertEqual(HeadingGeometry.continuousRotation(from: 720, to: 10), 730)
        XCTAssertEqual(HeadingGeometry.continuousRotation(from: -350, to: 20), -340)
    }

    func testContinuousRotationBreaksTheHalfTurnTieAnticlockwise() {
        // Either direction is 180°; the implementation picks anticlockwise. Pinned so a
        // refactor cannot silently make the cone flip direction on the tie.
        XCTAssertEqual(HeadingGeometry.continuousRotation(from: 0, to: 180), -180)
    }

    func testApertureClampsAndPassesNilThrough() {
        XCTAssertNil(HeadingGeometry.apertureDegrees(forAccuracy: nil))
        XCTAssertNil(HeadingGeometry.apertureDegrees(forAccuracy: -1))
        XCTAssertEqual(HeadingGeometry.apertureDegrees(forAccuracy: 5), 45)
        XCTAssertEqual(HeadingGeometry.apertureDegrees(forAccuracy: 30), 60)
        XCTAssertEqual(HeadingGeometry.apertureDegrees(forAccuracy: 80), 110)
    }
}
