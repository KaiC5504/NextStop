import XCTest
@testable import NextStop

final class TransitModeTests: XCTestCase {
    func testKnownProductClassesMap() {
        XCTAssertEqual(TransitMode(productClass: 1), .train)
        XCTAssertEqual(TransitMode(productClass: 2), .metro)
        XCTAssertEqual(TransitMode(productClass: 4), .lightRail)
        XCTAssertEqual(TransitMode(productClass: 5), .bus)
        XCTAssertEqual(TransitMode(productClass: 7), .coach)
        XCTAssertEqual(TransitMode(productClass: 9), .ferry)
        XCTAssertEqual(TransitMode(productClass: 11), .schoolBus)
    }

    /// TfNSW uses both 99 and 100 for walking legs in the same response. Missing this
    /// renders a walk as a bus, in bus blue, on the map.
    func testBothWalkClassesMap() {
        XCTAssertEqual(TransitMode(productClass: 99), .walk)
        XCTAssertEqual(TransitMode(productClass: 100), .walk)
        XCTAssertTrue(TransitMode(productClass: 100).isWalking)
    }

    func testMissingOrUnexpectedClassIsUnknown() {
        XCTAssertEqual(TransitMode(productClass: nil), .unknown)
        XCTAssertEqual(TransitMode(productClass: 42), .unknown)
        XCTAssertFalse(TransitMode(productClass: nil).isWalking)
    }

    /// `Leg.id` builds on `"\(mode)"`, which prints the case name — not the raw value.
    /// If either ever diverges, every saved leg rating silently stops matching its leg,
    /// so both spellings are pinned here.
    func testInterpolationAndRawValueStayTheCaseName() {
        let expected: [(TransitMode, String)] = [
            (.train, "train"), (.metro, "metro"), (.lightRail, "lightRail"),
            (.bus, "bus"), (.coach, "coach"), (.ferry, "ferry"),
            (.schoolBus, "schoolBus"), (.walk, "walk"), (.cycle, "cycle"),
            (.unknown, "unknown"),
        ]
        for (mode, name) in expected {
            XCTAssertEqual("\(mode)", name)
            XCTAssertEqual(mode.rawValue, name)
        }
    }

    func testCodableRoundTrip() throws {
        let modes: [TransitMode] = [
            .train, .metro, .lightRail, .bus, .coach, .ferry,
            .schoolBus, .walk, .cycle, .unknown,
        ]
        let data = try JSONEncoder().encode(modes)
        XCTAssertEqual(try JSONDecoder().decode([TransitMode].self, from: data), modes)
    }
}
