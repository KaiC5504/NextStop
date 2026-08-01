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

    /// A sheet whose content is shorter than the medium reveal measures medium == large.
    /// The medium candidate drops out so the sheet settles at `.large` — the name that
    /// releases the scroll lock — instead of `.medium` naming the same height and
    /// leaving the list permanently unscrollable.
    func testEqualMediumAndLargeResolveToLarge() {
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 400, projectedHeight: 500), .large)
        XCTAssertEqual(SheetPhysics.nearestDetent(peek: 100, medium: 400, large: 400, projectedHeight: 150), .peek)
    }

    func testActivationJumpIsSubtracted() {
        XCTAssertEqual(SheetPhysics.effectiveTranslation(5), 0)
        XCTAssertEqual(SheetPhysics.effectiveTranslation(-5), 0)
        XCTAssertEqual(SheetPhysics.effectiveTranslation(8), 0)
        XCTAssertEqual(SheetPhysics.effectiveTranslation(20), 12)
        XCTAssertEqual(SheetPhysics.effectiveTranslation(-20), -12)
    }

    func testVisibleHeightTracksInsideTheRange() {
        XCTAssertEqual(
            SheetPhysics.visibleHeight(target: 400, translation: 100, peek: 100, full: 700, topSlack: 80),
            300
        )
    }

    func testVisibleHeightRubberBandsPastBothEnds() {
        let below = SheetPhysics.visibleHeight(target: 100, translation: 250, peek: 100, full: 700, topSlack: 80)
        XCTAssertLessThan(below, 100)
        XCTAssertGreaterThan(below, 100 - 300)

        // The upward band saturates below the slack, so overshoot never outruns the
        // glass hidden behind the content.
        let above = SheetPhysics.visibleHeight(target: 700, translation: -10_000, peek: 100, full: 700, topSlack: 80)
        XCTAssertGreaterThan(above, 700)
        XCTAssertLessThan(above, 700 + 80)
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
