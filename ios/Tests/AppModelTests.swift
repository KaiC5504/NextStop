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
