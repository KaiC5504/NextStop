import XCTest
@testable import NextStop

final class JourneyBannerModelTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_753_900_000)

    private func state(
        phase: JourneyActivityPhase, mode: TransitMode = .train,
        routeBadge: String? = "T1", headsign: String? = "Penrith via Central",
        place: String, end: TimeInterval = 600,
        status: DepartureStatus = .onTime,
        stopIndex: Int? = nil, stopCount: Int? = nil, nextStopName: String? = nil,
        nextLegLine: String? = nil
    ) -> JourneyActivityAttributes.ContentState {
        JourneyActivityAttributes.ContentState(
            phase: phase, mode: mode, routeBadge: routeBadge, headsign: headsign,
            place: place, countdownStart: base.addingTimeInterval(min(0, end)),
            countdownEnd: base.addingTimeInterval(end),
            status: status, arrivalShort: "5:26 am",
            legIndex: 1, legCount: 3, nextLegLine: nextLegLine,
            stopIndex: stopIndex, stopCount: stopCount,
            nextStopName: nextStopName, stopFractions: nil
        )
    }

    func testWalkingBannerShowsDestinationAndRemainingMinutes() {
        let model = JourneyBannerModel.make(
            state: state(phase: .walking, mode: .walk, routeBadge: nil, place: "Chatswood Station", end: 540),
            now: base
        )
        XCTAssertEqual(model.title, "Walk to Chatswood Station")
        XCTAssertEqual(model.subtitle, "9 min")
        XCTAssertEqual(model.symbolName, "figure.walk")
    }

    func testWaitingBannerShowsRouteHeadsignCountdownAndPlatform() {
        let model = JourneyBannerModel.make(
            state: state(phase: .waiting, place: "Wynyard Station, Platform 3", end: 240),
            now: base
        )
        XCTAssertEqual(model.title, "Board T1 to Penrith via Central")
        XCTAssertEqual(model.subtitle, "in 4 min · Platform 3")
        XCTAssertEqual(model.tint, TransitMode.train.tint)
    }

    func testWaitingBannerFallsBackWhenRouteAndHeadsignAreMissing() {
        let model = JourneyBannerModel.make(
            state: state(phase: .waiting, routeBadge: nil, headsign: nil, place: "Chatswood Station", end: 120),
            now: base
        )
        XCTAssertEqual(model.title, "Board \(TransitMode.train.displayName)")
        XCTAssertEqual(model.subtitle, "in 2 min")
    }

    func testRidingBannerShowsAlightAndNextStop() {
        let model = JourneyBannerModel.make(
            state: state(
                phase: .riding, mode: .metro, routeBadge: "M1",
                place: "Central Station, Platform 16",
                stopIndex: 3, stopCount: 11, nextStopName: "St Leonards Station"
            ),
            now: base
        )
        XCTAssertEqual(model.title, "Alight at Central Station")
        XCTAssertEqual(model.subtitle, "Next stop St Leonards Station · stop 3 of 11")
        XCTAssertEqual(model.tint, TransitMode.metro.tint)
    }

    func testRidingBannerWithoutStopDataFallsBackToStatus() {
        let model = JourneyBannerModel.make(
            state: state(phase: .riding, place: "Central", status: .late(4)),
            now: base
        )
        XCTAssertEqual(model.subtitle, DepartureStatus.late(4).label)
    }

    func testArrivedBanner() {
        let model = JourneyBannerModel.make(
            state: state(phase: .arrived, place: "The University of Sydney"),
            now: base
        )
        XCTAssertEqual(model.title, "Arrived")
        XCTAssertEqual(model.subtitle, "The University of Sydney")
        XCTAssertEqual(model.symbolName, "checkmark.circle.fill")
        XCTAssertEqual(model.tint, Theme.Colors.onTime)
    }

    func testCountdownPastDepartureReadsNow() {
        let model = JourneyBannerModel.make(
            state: state(phase: .waiting, place: "Chatswood Station", end: -30),
            now: base
        )
        XCTAssertEqual(model.subtitle, "now")
    }

    func testWalkingCarriesTheThenChip() {
        let model = JourneyBannerModel.make(
            state: state(phase: .walking, mode: .walk, place: "Chatswood Station", nextLegLine: "Then T1 · 8:12 am"),
            now: base
        )
        XCTAssertEqual(model.thenLine, "Then T1 · 8:12 am")
    }

    func testWaitingSuppressesTheThenChip() {
        // While waiting the banner already says "Board T1…" — the chip would repeat it.
        let model = JourneyBannerModel.make(
            state: state(phase: .waiting, place: "Chatswood, Platform 2", nextLegLine: "Then T1 · 8:12 am"),
            now: base
        )
        XCTAssertNil(model.thenLine)
    }

    func testRidingAndArrivedHaveNoThenChip() {
        XCTAssertNil(JourneyBannerModel.make(
            state: state(phase: .riding, place: "Central", nextLegLine: "Then T1 · 8:12 am"), now: base
        ).thenLine)
        XCTAssertNil(JourneyBannerModel.make(
            state: state(phase: .arrived, place: "Central", nextLegLine: "Then T1 · 8:12 am"), now: base
        ).thenLine)
    }
}
