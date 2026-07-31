import CoreLocation
import Foundation

/// Hand-built journeys for CI screenshots. CI has no API key, so without these the
/// route list and live journey screens cannot be seen before a TestFlight build. Times
/// are relative to launch so the metro leg is always mid-ride when the shot is taken.
enum DemoJourney {
    static func journeys(around now: Date) -> [Journey] {
        [metroJourney(now), busJourney(now), trainJourney(now)]
    }

    static let destination = StopSuggestion(
        id: "demo-usyd", name: "The University of Sydney", isBest: true
    )

    /// Walk → M1 (boarded six minutes ago, uneven stop gaps) → walk.
    private static func metroJourney(_ now: Date) -> Journey {
        let boarded = now.addingTimeInterval(-360)
        let stops = metroStops(from: boarded)
        let alight = stops.last!.arrival!
        let legs = [
            walkLeg(
                id: "demo-m1-walk-in", to: "Chatswood Station",
                departure: boarded.addingTimeInterval(-300), seconds: 240,
                from: (-33.7952, 151.1789), toCoord: (-33.7969, 151.1803)
            ),
            Leg(
                id: "demo-m1", mode: .metro, route: "M1", headsign: "Sydenham",
                originName: "Chatswood Station", destinationName: "Central Station",
                plannedDeparture: boarded, estimatedDeparture: boarded,
                plannedArrival: alight, estimatedArrival: alight,
                hasRealtime: true, path: stops.map(\.coordinate), stops: stops,
                durationSeconds: Int(alight.timeIntervalSince(boarded))
            ),
            walkLeg(
                id: "demo-m1-walk-out", to: "The University of Sydney",
                departure: alight.addingTimeInterval(60), seconds: 900,
                from: (-33.8832, 151.2065), toCoord: (-33.8886, 151.1873)
            ),
        ]
        return Journey(id: "demo-metro", legs: legs)
    }

    /// Walk → 428 running three minutes late → walk.
    private static func busJourney(_ now: Date) -> Journey {
        let planned = now.addingTimeInterval(9 * 60)
        let estimated = planned.addingTimeInterval(180)
        let arrival = estimated.addingTimeInterval(26 * 60)
        let names = [
            "Chatswood Interchange, Stand B", "Mowbray Rd", "Epping Rd",
            "Crows Nest", "North Sydney", "Railway Square",
        ]
        let stops = rideStops(prefix: "demo-428", names: names, start: estimated, gaps: [4, 9, 13, 18, 26])
        let legs = [
            walkLeg(
                id: "demo-428-walk-in", to: "Chatswood Interchange",
                departure: now.addingTimeInterval(5 * 60), seconds: 180,
                from: (-33.7952, 151.1789), toCoord: (-33.7975, 151.1810)
            ),
            Leg(
                id: "demo-428", mode: .bus, route: "428", headsign: "Railway Square",
                originName: "Chatswood Interchange, Stand B", destinationName: "Railway Square",
                plannedDeparture: planned, estimatedDeparture: estimated,
                plannedArrival: arrival.addingTimeInterval(-180), estimatedArrival: arrival,
                hasRealtime: true, path: stops.map(\.coordinate), stops: stops,
                durationSeconds: 26 * 60
            ),
            walkLeg(
                id: "demo-428-walk-out", to: "The University of Sydney",
                departure: arrival.addingTimeInterval(60), seconds: 300,
                from: (-33.8832, 151.2065), toCoord: (-33.8886, 151.1873)
            ),
        ]
        return Journey(id: "demo-bus", legs: legs)
    }

    /// Walk → T1 with no realtime → walk: the scheduled-only styling.
    private static func trainJourney(_ now: Date) -> Journey {
        let departure = now.addingTimeInterval(20 * 60)
        let arrival = departure.addingTimeInterval(18 * 60)
        let names = ["Chatswood Station", "Artarmon", "St Leonards", "North Sydney", "Central Station"]
        let stops = rideStops(prefix: "demo-t1", names: names, start: departure, gaps: [3, 6, 10, 18])
        let legs = [
            walkLeg(
                id: "demo-t1-walk-in", to: "Chatswood Station",
                departure: departure.addingTimeInterval(-300), seconds: 240,
                from: (-33.7952, 151.1789), toCoord: (-33.7969, 151.1803)
            ),
            Leg(
                id: "demo-t1", mode: .train, route: "T1", headsign: "Central via Gordon",
                originName: "Chatswood Station", destinationName: "Central Station",
                plannedDeparture: departure, estimatedDeparture: nil,
                plannedArrival: arrival, estimatedArrival: nil,
                hasRealtime: false, path: stops.map(\.coordinate), stops: stops,
                durationSeconds: 18 * 60
            ),
            walkLeg(
                id: "demo-t1-walk-out", to: "The University of Sydney",
                departure: arrival.addingTimeInterval(60), seconds: 420,
                from: (-33.8832, 151.2065), toCoord: (-33.8886, 151.1873)
            ),
        ]
        return Journey(id: "demo-train", legs: legs)
    }

    private static let metroStations: [(String, Double, Double)] = [
        ("Chatswood", -33.7969, 151.1803),
        ("Crows Nest", -33.8265, 151.2003),
        ("Victoria Cross", -33.8390, 151.2072),
        ("Barangaroo", -33.8630, 151.2015),
        ("Martin Place", -33.8679, 151.2100),
        ("Gadigal", -33.8760, 151.2085),
        ("Central", -33.8832, 151.2065),
    ]

    /// Deliberately uneven gaps (minutes) so the tick marks and fill are visibly not
    /// equally spaced in the screenshot.
    private static func metroStops(from boarded: Date) -> [LegStop] {
        let gaps: [Double] = [3, 5.5, 9, 10.5, 12, 14]
        return metroStations.enumerated().map { index, station in
            let arrival = index == 0 ? nil : boarded.addingTimeInterval(gaps[index - 1] * 60)
            let departure = index == metroStations.count - 1
                ? nil : (arrival ?? boarded).addingTimeInterval(index == 0 ? 0 : 30)
            return LegStop(
                id: "demo-m1-\(index)", name: station.0,
                coordinate: CLLocationCoordinate2D(latitude: station.1, longitude: station.2),
                departure: departure, arrival: arrival
            )
        }
    }

    /// Stops strung along a straight line between Chatswood and Central — the map is not
    /// the point of these two journeys.
    private static func rideStops(prefix: String, names: [String], start: Date, gaps: [Double]) -> [LegStop] {
        names.enumerated().map { index, name in
            let fraction = Double(index) / Double(names.count - 1)
            let arrival = index == 0 ? nil : start.addingTimeInterval(gaps[index - 1] * 60)
            let departure = index == names.count - 1
                ? nil : (arrival ?? start).addingTimeInterval(index == 0 ? 0 : 30)
            return LegStop(
                id: "\(prefix)-\(index)", name: name,
                coordinate: CLLocationCoordinate2D(
                    latitude: -33.7969 + fraction * (-33.8832 - -33.7969),
                    longitude: 151.1803 + fraction * (151.2065 - 151.1803)
                ),
                departure: departure, arrival: arrival
            )
        }
    }

    private static func walkLeg(
        id: String, to destination: String, departure: Date, seconds: Int,
        from: (Double, Double), toCoord: (Double, Double)
    ) -> Leg {
        Leg(
            id: id, mode: .walk, route: nil, headsign: nil,
            originName: "", destinationName: destination,
            plannedDeparture: departure, estimatedDeparture: nil,
            plannedArrival: departure.addingTimeInterval(Double(seconds)), estimatedArrival: nil,
            hasRealtime: false,
            path: [
                CLLocationCoordinate2D(latitude: from.0, longitude: from.1),
                CLLocationCoordinate2D(latitude: toCoord.0, longitude: toCoord.1),
            ],
            stops: [], durationSeconds: seconds
        )
    }
}

extension AppModel {
    /// A model pre-loaded with the demo journeys and nothing live behind it — no
    /// network, no ActivityKit — for `-initialScreen options` / `journey` screenshots.
    static func demo() -> AppModel {
        let model = AppModel(isDemo: true)
        let journeys = DemoJourney.journeys(around: Date())
        model.destination = DemoJourney.destination
        model.journeys = journeys
        model.selectedJourneyID = journeys.first?.id
        model.phase = .ready
        return model
    }
}
