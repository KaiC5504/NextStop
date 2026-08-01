import CoreLocation
import XCTest
@testable import NextStop

final class JourneyOptionRowModelTests: XCTestCase {
    /// 1:30 pm AEDT — the pinned instant TimeDisplayTests uses.
    private let base = Date(timeIntervalSince1970: 1_767_580_200)

    private func walk(_ id: String, departure: TimeInterval, seconds: Int) -> Leg {
        Leg(
            id: id, mode: .walk, route: nil, headsign: nil,
            originName: "", destinationName: "somewhere",
            plannedDeparture: base.addingTimeInterval(departure), estimatedDeparture: nil,
            plannedArrival: base.addingTimeInterval(departure + Double(seconds)), estimatedArrival: nil,
            hasRealtime: false, path: [], stops: [], durationSeconds: seconds
        )
    }

    private func transit(
        _ id: String, route: String, origin: String,
        plannedDeparture: TimeInterval, estimatedDeparture: TimeInterval? = nil,
        arrival: TimeInterval
    ) -> Leg {
        Leg(
            id: id, mode: .train, route: route, headsign: "Somewhere",
            originName: origin, destinationName: "there",
            plannedDeparture: base.addingTimeInterval(plannedDeparture),
            estimatedDeparture: estimatedDeparture.map(base.addingTimeInterval),
            plannedArrival: base.addingTimeInterval(arrival), estimatedArrival: nil,
            hasRealtime: estimatedDeparture != nil, path: [], stops: [], durationSeconds: nil
        )
    }

    func testTimesAndDurationDerive() {
        let journey = Journey(id: "j", legs: [
            walk("w1", departure: 0, seconds: 300),
            transit("t", route: "T1", origin: "Chatswood Station", plannedDeparture: 360, arrival: 2_280),
            walk("w2", departure: 2_340, seconds: 240),
        ])
        let model = JourneyOptionRowModel(journey: journey)
        XCTAssertEqual(model.times, "1:30 – 2:13 pm")
        XCTAssertEqual(model.duration, "43 min")
    }

    func testStatusComesFromTheFirstTransitLegWithCleanedOrigin() {
        let first = transit(
            "t1", route: "T1", origin: "Chatswood Station, Platform 1",
            plannedDeparture: 300, estimatedDeparture: 480, arrival: 1_200
        )
        let second = transit("t2", route: "T9", origin: "Strathfield Station", plannedDeparture: 1_500, arrival: 2_400)
        let journey = Journey(id: "j", legs: [walk("w", departure: 0, seconds: 240), first, second])
        let model = JourneyOptionRowModel(journey: journey)
        XCTAssertEqual(model.status, DepartureStatus(leg: first))
        XCTAssertNotEqual(model.status, DepartureStatus(leg: second))
        XCTAssertEqual(model.statusDetail, "1:38 pm from Chatswood Station")
    }

    func testAllWalkJourneyHasNoStatusLine() {
        let model = JourneyOptionRowModel(journey: Journey(id: "j", legs: [walk("w", departure: 0, seconds: 600)]))
        XCTAssertNil(model.status)
        XCTAssertNil(model.statusDetail)
        XCTAssertEqual(model.duration, "10 min")
    }

    func testMissingTimesHideThemselves() {
        let timeless = Leg(
            id: "x", mode: .train, route: "T1", headsign: nil,
            originName: "A", destinationName: "B",
            plannedDeparture: nil, estimatedDeparture: nil,
            plannedArrival: nil, estimatedArrival: nil,
            hasRealtime: false, path: [], stops: [], durationSeconds: nil
        )
        let model = JourneyOptionRowModel(journey: Journey(id: "j", legs: [timeless]))
        XCTAssertNil(model.times)
        XCTAssertNil(model.duration)
        XCTAssertNil(model.statusDetail)
        XCTAssertNotNil(model.status)
    }
}
