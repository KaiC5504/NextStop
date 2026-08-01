import XCTest
@testable import NextStop

final class SpyNotificationCenter: NotificationScheduling {
    var authorize = true
    var pending: [String] = []
    private(set) var added: [AlightAlert] = []
    private(set) var removed: [String] = []
    private(set) var authorizationRequests = 0

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return authorize
    }

    func add(_ alert: AlightAlert) async { added.append(alert) }
    func removePending(ids: [String]) { removed.append(contentsOf: ids) }
    func pendingAlertIDs() async -> [String] { pending }
}

final class AlightAlertTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_753_900_000)

    private func leg(
        id: String, mode: TransitMode = .train, destination: String = "Central",
        arrival: TimeInterval?
    ) -> Leg {
        Leg(
            id: id, mode: mode, route: mode == .walk ? nil : "T1", headsign: nil,
            originName: "A", destinationName: destination,
            plannedDeparture: base, estimatedDeparture: nil,
            plannedArrival: arrival.map(base.addingTimeInterval), estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: nil
        )
    }

    private func journey(trainArrival: TimeInterval = 1_200) -> Journey {
        Journey(id: "j", legs: [
            leg(id: "walk", mode: .walk, destination: "Chatswood", arrival: 300),
            leg(id: "train", destination: "Central", arrival: trainArrival),
            leg(id: "bus", mode: .bus, destination: "USyd", arrival: 2_400),
        ])
    }

    // MARK: Planner

    func testOneAlertPerTransitLegAtTheLead() {
        let alerts = AlightAlertPlanner.alerts(for: journey(), now: base)
        XCTAssertEqual(alerts.map(\.id), ["alight-train", "alight-bus"])
        XCTAssertEqual(alerts[0].fireDate, base.addingTimeInterval(1_200 - 150))
        XCTAssertEqual(alerts[0].stopName, "Central")
        XCTAssertTrue(alerts[0].body.contains("Central"), alerts[0].body)
    }

    func testLegsWithoutAnArrivalAreSkipped() {
        let journey = Journey(id: "j", legs: [leg(id: "train", arrival: nil)])
        XCTAssertTrue(AlightAlertPlanner.alerts(for: journey, now: base).isEmpty)
    }

    /// Inside the lead window the alert falls back to a fixed last-call moment — fixed,
    /// so every 30-second replan derives the same alert instead of re-arming forever.
    func testJoiningInsideTheLeadWindowFallsBackToLastCall() {
        let now = base.addingTimeInterval(1_200 - 100)
        let alerts = AlightAlertPlanner.alerts(for: journey(), now: now)
        XCTAssertEqual(alerts.first?.fireDate, base.addingTimeInterval(1_200 - 60))
    }

    func testTooCloseToArrivalIsDropped() {
        let now = base.addingTimeInterval(1_200 - 30)
        let alerts = AlightAlertPlanner.alerts(for: journey(), now: now)
        XCTAssertEqual(alerts.map(\.id), ["alight-bus"], "the train alert has nothing left to say")
    }

    func testDiffIsEmptyWhenNothingMoved() {
        let planned = AlightAlertPlanner.alerts(for: journey(), now: base)
        let (add, removeIDs) = AlightAlertPlanner.diff(planned: planned, scheduled: planned, now: base)
        XCTAssertTrue(add.isEmpty)
        XCTAssertTrue(removeIDs.isEmpty)
    }

    func testAMovedEstimateReArmsTheAlert() {
        let scheduled = AlightAlertPlanner.alerts(for: journey(), now: base)
        let planned = AlightAlertPlanner.alerts(for: journey(trainArrival: 1_500), now: base)
        let (add, removeIDs) = AlightAlertPlanner.diff(planned: planned, scheduled: scheduled, now: base)
        XCTAssertEqual(add.map(\.id), ["alight-train"])
        XCTAssertTrue(removeIDs.isEmpty, "same id — the center replaces it")
    }

    func testSwappingJourneysRemovesTheOldAlerts() {
        let scheduled = AlightAlertPlanner.alerts(for: journey(), now: base)
        let other = Journey(id: "k", legs: [leg(id: "ferry", mode: .ferry, arrival: 900)])
        let planned = AlightAlertPlanner.alerts(for: other, now: base)
        let (add, removeIDs) = AlightAlertPlanner.diff(planned: planned, scheduled: scheduled, now: base)
        XCTAssertEqual(add.map(\.id), ["alight-ferry"])
        XCTAssertEqual(Set(removeIDs), ["alight-train", "alight-bus"])
    }

    /// Once an alert has fired, a moved estimate must not ring the same stop twice.
    func testAFiredAlertIsNeverReArmed() {
        let scheduled = AlightAlertPlanner.alerts(for: journey(), now: base)
        let afterFiring = base.addingTimeInterval(1_200 - 120)
        let planned = AlightAlertPlanner.alerts(for: journey(trainArrival: 1_260), now: afterFiring)
        let (add, _) = AlightAlertPlanner.diff(planned: planned, scheduled: scheduled, now: afterFiring)
        XCTAssertFalse(add.contains { $0.id == "alight-train" })
    }

    // MARK: Scheduler

    @MainActor
    func testBeginAsksOnceSweepsOrphansAndArms() async {
        let spy = SpyNotificationCenter()
        spy.pending = ["alight-stale-from-last-run"]
        let scheduler = AlightAlertScheduler(center: spy)
        await scheduler.begin(journey: journey(), now: base)
        XCTAssertEqual(spy.removed, ["alight-stale-from-last-run"])
        XCTAssertEqual(spy.added.map(\.id), ["alight-train", "alight-bus"])

        await scheduler.sync(journey: journey(), now: base.addingTimeInterval(30))
        XCTAssertEqual(spy.added.count, 2, "steady estimates must not re-arm anything")
    }

    @MainActor
    func testDeclinedAuthorizationSchedulesNothing() async {
        let spy = SpyNotificationCenter()
        spy.authorize = false
        let scheduler = AlightAlertScheduler(center: spy)
        await scheduler.begin(journey: journey(), now: base)
        XCTAssertTrue(spy.added.isEmpty)
    }

    /// The launch sweep must clean up without ever raising the permission prompt — a
    /// dialog at launch on the CI simulator would park over every later screenshot.
    @MainActor
    func testLaunchSweepRemovesEveryPendingAlightAlertWithoutPrompting() async {
        let spy = SpyNotificationCenter()
        spy.pending = ["alight-a", "alight-b"]
        let scheduler = AlightAlertScheduler(center: spy)
        await scheduler.sweepOrphansAtLaunch()
        XCTAssertEqual(Set(spy.removed), ["alight-a", "alight-b"])
        XCTAssertEqual(spy.authorizationRequests, 0)
    }

    @MainActor
    func testLaunchSweepWithNothingPendingRemovesNothing() async {
        let spy = SpyNotificationCenter()
        let scheduler = AlightAlertScheduler(center: spy)
        await scheduler.sweepOrphansAtLaunch()
        XCTAssertTrue(spy.removed.isEmpty)
        XCTAssertEqual(spy.authorizationRequests, 0)
    }

    @MainActor
    func testCancelAllRemovesEverythingArmed() async {
        let spy = SpyNotificationCenter()
        let scheduler = AlightAlertScheduler(center: spy)
        await scheduler.begin(journey: journey(), now: base)
        scheduler.cancelAll()
        XCTAssertEqual(Set(spy.removed), ["alight-train", "alight-bus"])
    }
}
