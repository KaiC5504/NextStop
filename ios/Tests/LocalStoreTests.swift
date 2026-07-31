import XCTest
@testable import NextStop

final class LocalStoreTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func suggestion(_ id: String) -> StopSuggestion {
        StopSuggestion(id: id, name: "Stop \(id)", isBest: false)
    }

    func testRecentsAreMostRecentFirstAndDeduplicated() {
        let store = LocalStore(fileURL: url)
        store.addRecent(suggestion("a"))
        store.addRecent(suggestion("b"))
        store.addRecent(suggestion("a"))
        XCTAssertEqual(store.recents.map(\.id), ["a", "b"])
    }

    func testRecentsAreCappedAtTen() {
        let store = LocalStore(fileURL: url)
        for index in 0..<15 { store.addRecent(suggestion("\(index)")) }
        XCTAssertEqual(store.recents.count, 10)
        XCTAssertEqual(store.recents.first?.id, "14")
    }

    func testSavedTogglesBothWays() {
        let store = LocalStore(fileURL: url)
        store.toggleSaved(suggestion("a"))
        XCTAssertTrue(store.isSaved(suggestion("a")))
        store.toggleSaved(suggestion("a"))
        XCTAssertFalse(store.isSaved(suggestion("a")))
    }

    func testEverythingSurvivesAReload() throws {
        let store = LocalStore(fileURL: url)
        store.addRecent(suggestion("a"))
        store.toggleSaved(suggestion("b"))
        store.record(PredictionFeedback(
            id: UUID(), recordedAt: Date(), wasCorrect: false, mode: "Bus", route: "412",
            originName: "Railway Square", destinationName: "USyd",
            plannedDeparture: nil, estimatedDeparture: nil, hadRealtime: true, errorSeconds: 120
        ))

        let reloaded = LocalStore(fileURL: url)
        XCTAssertEqual(reloaded.recents.map(\.id), ["a"])
        XCTAssertEqual(reloaded.saved.map(\.id), ["b"])
        XCTAssertEqual(reloaded.feedback.count, 1)
        XCTAssertEqual(reloaded.feedback[0].errorSeconds, 120)
    }

    /// A tap is worth more than a verdict: the gap between the predicted departure and the
    /// moment the user tapped is the measurable error.
    func testFeedbackFromALegComputesErrorAgainstTheTapTime() {
        let planned = Date(timeIntervalSince1970: 1_000_000)
        let leg = Leg(
            id: "test", mode: .bus, route: "412", headsign: "USyd",
            originName: "Railway Square", destinationName: "USyd",
            plannedDeparture: planned, estimatedDeparture: planned.addingTimeInterval(60),
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: 600
        )
        let feedback = PredictionFeedback(leg: leg, wasCorrect: true, tappedAt: planned.addingTimeInterval(150))
        XCTAssertEqual(feedback.errorSeconds, 90)
        XCTAssertEqual(feedback.mode, "Bus")
        XCTAssertTrue(feedback.hadRealtime)
    }

    /// The journey screen asks the store which legs are already rated. Holding that in the
    /// view's own state let a leg be rated twice by navigating back to the map and returning.
    func testRatedLegIDsSurviveAReload() {
        let leg = Leg(
            id: "metro|M1|Chatswood Station|1000000", mode: .metro, route: "M1", headsign: "Sydenham",
            originName: "Chatswood Station", destinationName: "Central",
            plannedDeparture: Date(timeIntervalSince1970: 1_000_000), estimatedDeparture: nil,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: 900
        )
        let store = LocalStore(fileURL: url)
        XCTAssertFalse(store.ratedLegIDs.contains(leg.id))
        store.record(PredictionFeedback(leg: leg, wasCorrect: true, tappedAt: Date()))
        XCTAssertTrue(store.ratedLegIDs.contains(leg.id))

        XCTAssertTrue(LocalStore(fileURL: url).ratedLegIDs.contains(leg.id))
    }

    /// Records written before `legID` existed must still decode. If they threw, the whole
    /// store would reset and take the user's saved places with it.
    func testFeedbackWithoutALegIDStillDecodes() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","recordedAt":"2026-07-28T09:03:00Z","wasCorrect":true,
          "mode":"Bus","originName":"A","destinationName":"B","hadRealtime":true}]
        """
        let decoded = try JSONDecoder.tfnswDecoder.decode(
            [PredictionFeedback].self, from: Data(legacy.utf8)
        )
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].legID)
    }

    func testExportIsDecodableJSON() throws {
        let store = LocalStore(fileURL: url)
        store.record(PredictionFeedback(
            id: UUID(), recordedAt: Date(), wasCorrect: true, mode: "Metro", route: "M1",
            originName: "Chatswood", destinationName: "Central",
            plannedDeparture: nil, estimatedDeparture: nil, hadRealtime: true, errorSeconds: 0
        ))
        let decoded = try JSONDecoder.tfnswDecoder.decode(
            [PredictionFeedback].self, from: try store.exportFeedbackJSON()
        )
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].mode, "Metro")
    }
}
