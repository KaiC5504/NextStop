import XCTest
@testable import NextStop

@MainActor
final class AppModelTests: XCTestCase {
    private func model(status: Int = 200, payload: Data = Data()) -> AppModel {
        AppModel(
            client: TfNSWClient(session: StubFetcher(status: status, payload: payload), keyProvider: { "k" }),
            store: LocalStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).json"))
        )
    }

    private let usyd = StopSuggestion(id: "2", name: "USyd", isBest: true)

    func testPlanningPopulatesJourneysAndSelectsTheFirst() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.journeys.isEmpty)
        XCTAssertEqual(model.selectedJourneyID, model.journeys.first?.id)
        XCTAssertNotNil(model.selectedJourney)
    }

    func testPlanningRecordsTheDestinationAsRecent() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        XCTAssertEqual(model.store.recents.first?.id, "2")
    }

    /// The user's chosen option must survive a refresh, and a refresh must not append a
    /// duplicate recent every 30 seconds.
    func testRefreshKeepsTheSelectionAndDoesNotDuplicateRecents() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        let chosen = model.journeys.last?.id
        model.selectedJourneyID = chosen
        await model.refresh()
        XCTAssertEqual(model.selectedJourneyID, chosen)
        XCTAssertEqual(model.store.recents.count, 1)
    }

    /// A successful request that returns nothing must not look like the idle screen. This
    /// is the state that hid a POI destination resolving to no journeys at all.
    func testAnEmptyResultIsItsOwnPhaseRatherThanReady() async {
        let model = model(payload: Data(#"{"journeys":[]}"#.utf8))
        await model.plan(to: usyd)
        XCTAssertEqual(model.phase, .noService)
        XCTAssertTrue(model.journeys.isEmpty)
    }

    func testPlanningSendsTheDestinationAsAnyType() async {
        let log = RequestLog()
        let model = AppModel(
            client: TfNSWClient(
                session: StubFetcher(payload: Fixture.data("trip-sample"), log: log),
                keyProvider: { "k" }
            ),
            store: LocalStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).json"))
        )
        await model.plan(to: StopSuggestion(id: "poiID:858286183:1:USyd", name: "USyd", isBest: true))
        XCTAssertTrue(log.last.contains("type_destination=any"), log.last)
    }

    /// Dismissing the search field must not wipe the banner telling the user their key was
    /// rejected — the field sits directly above that banner.
    func testClearingSearchLeavesAPlanFailureVisible() async {
        let model = model(status: 401)
        await model.plan(to: usyd)
        model.clearSearch()
        XCTAssertEqual(model.phase, .failed(.unauthorised))
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    func testAnUnauthorisedPlanSurfacesTheError() async {
        let model = model(status: 401)
        await model.plan(to: usyd)
        XCTAssertEqual(model.phase, .failed(.unauthorised))
        XCTAssertTrue(model.journeys.isEmpty)
    }

    func testShortQueriesDoNotSearch() async {
        let model = model(payload: Fixture.data("stopfinder-sample"))
        await model.search("Ch")
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    func testSearchPopulatesResults() async {
        let model = model(payload: Fixture.data("stopfinder-sample"))
        await model.search("Chatswood")
        XCTAssertFalse(model.searchResults.isEmpty)
    }

    /// Search and planning must not share error state, or a keystroke wipes the banner
    /// telling the user their key was rejected.
    func testSearchDoesNotClearAPlanFailure() async {
        let model = model(status: 401)
        await model.plan(to: usyd)
        await model.search("Ch")
        XCTAssertEqual(model.phase, .failed(.unauthorised))
    }

    func testResetClearsEverything() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.plan(to: usyd)
        model.reset()
        XCTAssertTrue(model.journeys.isEmpty)
        XCTAssertNil(model.destination)
        XCTAssertEqual(model.phase, .idle)
    }
}
