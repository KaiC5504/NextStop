import XCTest
@testable import NextStop

final class StopProgressTests: XCTestCase {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { base.addingTimeInterval(seconds) }

    func testPositionClampsAtBothEnds() {
        let times = [at(0), at(60), at(180)]
        XCTAssertEqual(StopProgress.position(times: times, now: at(-30)), 0)
        XCTAssertEqual(StopProgress.position(times: times, now: at(0)), 0)
        XCTAssertEqual(StopProgress.position(times: times, now: at(180)), 2)
        XCTAssertEqual(StopProgress.position(times: times, now: at(500)), 2)
    }

    func testPositionInterpolatesWithinASegment() {
        let times = [at(0), at(60), at(180)]
        XCTAssertEqual(StopProgress.position(times: times, now: at(30)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(StopProgress.position(times: times, now: at(120)), 1.5, accuracy: 0.0001)
        XCTAssertEqual(StopProgress.position(times: times, now: at(60)), 1, accuracy: 0.0001)
    }

    func testPositionDegenerateInputs() {
        XCTAssertEqual(StopProgress.position(times: [], now: at(0)), 0)
        XCTAssertEqual(StopProgress.position(times: [at(0)], now: at(100)), 0)
    }

    func testPassedCountMovesInWholeStops() {
        let times = [at(0), at(60), at(180)]
        XCTAssertEqual(StopProgress.passedCount(times: times, now: at(-1)), 0)
        XCTAssertEqual(StopProgress.passedCount(times: times, now: at(0)), 1)
        XCTAssertEqual(StopProgress.passedCount(times: times, now: at(59)), 1)
        XCTAssertEqual(StopProgress.passedCount(times: times, now: at(60)), 2)
        XCTAssertEqual(StopProgress.passedCount(times: times, now: at(999)), 3)
    }

    func testTickFractionsQuantizeAndAscend() {
        let fractions = StopProgress.tickFractions(
            times: [at(180), at(300), at(840)], start: at(0), end: at(1_200)
        )
        XCTAssertEqual(fractions, [0.15, 0.25, 0.7])
    }

    func testTickFractionsStayInsideTheEndCaps() {
        let fractions = StopProgress.tickFractions(
            times: [at(-50), at(600), at(2_000)], start: at(0), end: at(1_200)
        )
        XCTAssertEqual(fractions, [0.001, 0.5, 0.999])
    }

    /// Two stops seconds apart in a long leg land on the same 3-decimal fraction; one
    /// tick is enough to draw.
    func testTickFractionsCollapseDuplicates() {
        let fractions = StopProgress.tickFractions(
            times: [at(600), at(601), at(5_400)], start: at(0), end: at(10_800)
        )
        XCTAssertEqual(fractions, [0.056, 0.5])
    }

    func testTickFractionsEmptyWhenRangeIsDegenerate() {
        XCTAssertEqual(StopProgress.tickFractions(times: [at(10)], start: at(0), end: at(0)), [])
        XCTAssertEqual(StopProgress.tickFractions(times: [at(10)], start: at(60), end: at(0)), [])
        XCTAssertEqual(StopProgress.tickFractions(times: [], start: at(0), end: at(60)), [])
    }

    func testSpineFillHeightReducesToUniformWhenRowsMatch() {
        XCTAssertEqual(StopProgress.spineFillHeight(position: 1, stopCount: 4, rowHeight: 28, finalRowHeight: 28), 0)
        XCTAssertEqual(StopProgress.spineFillHeight(position: 2, stopCount: 4, rowHeight: 28, finalRowHeight: 28), 28)
        XCTAssertEqual(StopProgress.spineFillHeight(position: 3, stopCount: 4, rowHeight: 28, finalRowHeight: 28), 56)
    }

    /// The alighting row is taller, so the last segment stretches to reach its dot's
    /// centre: rows [28, 28, 56] put segments at [28, 42].
    func testSpineFillHeightStretchesTheFinalSegment() {
        XCTAssertEqual(StopProgress.spineFillHeight(position: 2, stopCount: 4, rowHeight: 28, finalRowHeight: 56), 28)
        XCTAssertEqual(StopProgress.spineFillHeight(position: 2.5, stopCount: 4, rowHeight: 28, finalRowHeight: 56), 49)
        XCTAssertEqual(StopProgress.spineFillHeight(position: 3, stopCount: 4, rowHeight: 28, finalRowHeight: 56), 70)
    }

    func testSpineFillHeightClampsAndDegenerates() {
        XCTAssertEqual(StopProgress.spineFillHeight(position: 0, stopCount: 4, rowHeight: 28, finalRowHeight: 56), 0)
        XCTAssertEqual(StopProgress.spineFillHeight(position: 99, stopCount: 4, rowHeight: 28, finalRowHeight: 56), 70)
        XCTAssertEqual(StopProgress.spineFillHeight(position: 1, stopCount: 2, rowHeight: 28, finalRowHeight: 56), 0)
    }
}
