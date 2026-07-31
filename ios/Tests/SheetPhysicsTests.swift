import XCTest
@testable import NextStop

final class SheetPhysicsTests: XCTestCase {
    func testProjectionAddsDecayedVelocity() {
        XCTAssertEqual(SheetPhysics.projectedEnd(position: 100, velocity: 0), 100)
        XCTAssertEqual(SheetPhysics.projectedEnd(position: 0, velocity: 1_000), 99, accuracy: 0.5)
    }

    func testNearestDetentSplitsAtTheMidpoint() {
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, projectedHeight: 240), .peek)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, projectedHeight: 260), .medium)
    }

    /// The same finger position, released slowly versus flung: the fling must cross to
    /// the far detent even though the position alone would settle back. Momentum is the
    /// entire reason the projection exists.
    func testAFlingCrossesWhereASlowReleaseWouldNot() {
        let peek: CGFloat = 100, medium: CGFloat = 400, translation: CGFloat = -140

        let slow = peek - SheetPhysics.projectedEnd(position: translation, velocity: 0)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: peek, medium: medium, projectedHeight: slow), .peek)

        let flung = peek - SheetPhysics.projectedEnd(position: translation, velocity: -2_000)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: peek, medium: medium, projectedHeight: flung), .medium)
    }

    func testRubberBandResistsAndSaturates() {
        XCTAssertEqual(SheetPhysics.rubberBand(overshoot: 0), 0)
        XCTAssertLessThan(SheetPhysics.rubberBand(overshoot: 100), 100)
        XCTAssertGreaterThan(
            SheetPhysics.rubberBand(overshoot: 200),
            SheetPhysics.rubberBand(overshoot: 100)
        )
        XCTAssertLessThan(SheetPhysics.rubberBand(overshoot: 10_000), 300)
    }
}
