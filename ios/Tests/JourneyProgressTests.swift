import XCTest
@testable import NextStop

final class JourneyProgressTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_753_900_000)

    private var journey: Journey {
        let walk = Leg(
            id: "walk", mode: .walk, route: nil, headsign: nil,
            originName: "Home", destinationName: "Chatswood",
            plannedDeparture: base, estimatedDeparture: nil,
            plannedArrival: base.addingTimeInterval(300), estimatedArrival: nil,
            hasRealtime: false, path: [], stops: [], durationSeconds: 300
        )
        let train = Leg(
            id: "train", mode: .train, route: "T1", headsign: "Central",
            originName: "Chatswood", destinationName: "Central",
            plannedDeparture: base.addingTimeInterval(600), estimatedDeparture: nil,
            plannedArrival: base.addingTimeInterval(2_400), estimatedArrival: nil,
            hasRealtime: true, path: [], stops: [], durationSeconds: 1_800
        )
        return Journey(id: "j", legs: [walk, train])
    }

    /// "Active" includes the leg being waited for: the walk is done at +400 but the
    /// train has not arrived, so the train is what the map should emphasise.
    func testActiveLegIsTheFirstUnfinishedOne() {
        XCTAssertEqual(journey.activeLeg(at: base.addingTimeInterval(100))?.id, "walk")
        XCTAssertEqual(journey.activeLeg(at: base.addingTimeInterval(400))?.id, "train")
        XCTAssertEqual(journey.activeLeg(at: base.addingTimeInterval(1_000))?.id, "train")
    }

    func testNoActiveLegAfterTheJourneyEnds() {
        XCTAssertNil(journey.activeLeg(at: base.addingTimeInterval(3_000)))
    }
}
