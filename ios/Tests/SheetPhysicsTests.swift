import XCTest
@testable import NextStop

final class SheetPhysicsTests: XCTestCase {
    func testProjectionAddsDecayedVelocity() {
        XCTAssertEqual(SheetPhysics.projectedEnd(position: 100, velocity: 0), 100)
        XCTAssertEqual(SheetPhysics.projectedEnd(position: 0, velocity: 1_000), 99, accuracy: 0.5)
    }

    func testNearestDetentSplitsAtTheMidpoints() {
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 700, projectedHeight: 240), .peek)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 700, projectedHeight: 260), .medium)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 700, projectedHeight: 540), .medium)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 700, projectedHeight: 560), .large)
    }

    func testTiesResolveTowardTheSmallerDetent() {
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 700, projectedHeight: 250), .peek)
    }

    /// A sheet whose content is shorter than the medium reveal measures medium == large;
    /// projections past it must settle on `.medium`, not flap between two names for the
    /// same height.
    func testEqualMediumAndLargeCollapseToMedium() {
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 400, projectedHeight: 500), .medium)
    }

    /// The same finger position, released slowly versus flung: the fling must cross to
    /// the far detent even though the position alone would settle back. Momentum is the
    /// entire reason the projection exists.
    func testAFlingCrossesWhereASlowReleaseWouldNot() {
        let peek: CGFloat = 100, medium: CGFloat = 400, large: CGFloat = 800, translation: CGFloat = -140

        let slow = peek - SheetPhysics.projectedEnd(position: translation, velocity: 0)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: peek, medium: medium, large: large, projectedHeight: slow), .peek)

        let flung = peek - SheetPhysics.projectedEnd(position: translation, velocity: -2_000)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: peek, medium: medium, large: large, projectedHeight: flung), .medium)
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
