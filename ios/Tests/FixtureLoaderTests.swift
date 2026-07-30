import XCTest

final class FixtureLoaderTests: XCTestCase {
    /// One smoke test, not one per fixture. Later suites decode both files for real; this
    /// exists only to turn "resource not copied into the bundle" into a clear failure.
    func testFixturesAreBundled() throws {
        let trip = try JSONSerialization.jsonObject(with: Fixture.data("trip-sample")) as? [String: Any]
        XCTAssertFalse((trip?["journeys"] as? [[String: Any]] ?? []).isEmpty)

        let stops = try JSONSerialization.jsonObject(with: Fixture.data("stopfinder-sample")) as? [String: Any]
        XCTAssertFalse((stops?["locations"] as? [[String: Any]] ?? []).isEmpty)
    }
}
