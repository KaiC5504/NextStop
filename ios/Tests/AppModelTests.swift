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

    /// There is never a fix in the test environment, so every plan uses the Chatswood
    /// fallback — and the model must say so rather than pretend it knows where you are.
    func testPlanningWithoutAFixFlagsTheFallback() async {
        let model = model(payload: Fixture.data("trip-sample"))
        XCTAssertFalse(model.plannedFromFallback)
        await model.plan(to: usyd)
        XCTAssertTrue(model.plannedFromFallback)
        model.reset()
        XCTAssertFalse(model.plannedFromFallback)
    }

    func testArriveByReplansWithTheArrMacro() async {
        let log = RequestLog()
        let model = AppModel(
            client: TfNSWClient(
                session: StubFetcher(payload: Fixture.data("trip-sample"), log: log),
                keyProvider: { "k" }
            ),
            store: LocalStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).json"))
        )
        await model.plan(to: usyd)
        XCTAssertTrue(log.last.contains("depArrMacro=dep"), log.last)
        await model.setPlanTime(.arriveBy(Date().addingTimeInterval(3_600)))
        XCTAssertTrue(log.last.contains("depArrMacro=arr"), log.last)
        XCTAssertEqual(model.phase, .ready)
    }

    func testPlanTimeChosenBeforeADestinationIsStoredNotSent() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.setPlanTime(.departAt(Date().addingTimeInterval(600)))
        XCTAssertEqual(model.phase, .idle, "no destination — nothing to replan yet")
        XCTAssertNotEqual(model.planTimeSelection, .leaveNow)
    }

    func testResetRestoresLeaveNow() async {
        let model = model(payload: Fixture.data("trip-sample"))
        await model.setPlanTime(.arriveBy(Date().addingTimeInterval(3_600)))
        model.reset()
        XCTAssertEqual(model.planTimeSelection, .leaveNow)
    }

    /// Init must clean up notifications a force-quit stranded, without waiting for a
    /// journey screen to open — that was the gap that let stale alerts ring.
    func testInitSweepsOrphanedAlightAlerts() async {
        let spy = SpyNotificationCenter()
        spy.pending = ["alight-zombie"]
        _ = AppModel(
            client: TfNSWClient(session: StubFetcher(), keyProvider: { "k" }),
            store: LocalStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).json")),
            alightAlerts: AlightAlertScheduler(center: spy)
        )
        // The sweep is a fire-and-forget Task on this same actor: give it turns, not time.
        for _ in 0..<10 where spy.removed.isEmpty { await Task.yield() }
        XCTAssertEqual(spy.removed, ["alight-zombie"])
        XCTAssertEqual(spy.authorizationRequests, 0)
    }

    /// The background hold exists exactly while a journey is active. The spy scheduler
    /// is not optional: startJourneyActivity reaches the notification-permission path,
    /// and the real center's dialog would park over every CI screenshot.
    func testJourneyLifecycleRaisesAndDropsTheBackgroundHold() async {
        let spy = SpyNotificationCenter()
        let model = AppModel(
            client: TfNSWClient(
                session: StubFetcher(payload: Fixture.data("trip-sample")), keyProvider: { "k" }
            ),
            store: LocalStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).json")),
            alightAlerts: AlightAlertScheduler(center: spy)
        )
        await model.plan(to: usyd)
        XCTAssertFalse(model.isJourneyActive)
        model.startJourneyActivity()
        XCTAssertTrue(model.isJourneyActive)
        if LocationProvider.canHoldBackground(model.location.authorisation) {
            XCTAssertTrue(model.location.allowsBackgroundUpdates)
        }
        model.reset()
        XCTAssertFalse(model.isJourneyActive)
        XCTAssertFalse(model.location.allowsBackgroundUpdates)
    }

    /// The reset path must tear down whatever the shared scheduler armed.
    func testResetCancelsArmedAlightAlerts() async {
        let spy = SpyNotificationCenter()
        let scheduler = AlightAlertScheduler(center: spy)
        let model = AppModel(
            client: TfNSWClient(session: StubFetcher(), keyProvider: { "k" }),
            store: LocalStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("model-\(UUID().uuidString).json")),
            alightAlerts: scheduler
        )
        let train = Leg(
            id: "train", mode: .train, route: "T1", headsign: nil,
            originName: "A", destinationName: "Central",
            plannedDeparture: Date(), estimatedDeparture: nil,
            plannedArrival: Date().addingTimeInterval(3_600), estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: nil
        )
        await scheduler.begin(journey: Journey(id: "j", legs: [train]), now: Date())
        XCTAssertEqual(spy.added.map(\.id), ["alight-train"])
        model.reset()
        XCTAssertEqual(spy.removed, ["alight-train"])
    }
}
