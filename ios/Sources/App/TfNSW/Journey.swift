import CoreLocation
import Foundation

struct LegStop: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let departure: Date?
}

struct Leg: Identifiable {
    let id: String
    let mode: TransitMode
    let route: String?
    let headsign: String?
    let originName: String
    let destinationName: String
    let plannedDeparture: Date?
    let estimatedDeparture: Date?
    let plannedArrival: Date?
    let estimatedArrival: Date?
    let hasRealtime: Bool
    let path: [CLLocationCoordinate2D]
    let stops: [LegStop]
    let durationSeconds: Int?

    var departure: Date? { estimatedDeparture ?? plannedDeparture }
    var arrival: Date? { estimatedArrival ?? plannedArrival }

    /// Nil when there is no estimate to compare, which is different from zero. Zero means
    /// "tracked and on time"; nil means "nobody is tracking this".
    var delaySeconds: Int? {
        guard let planned = plannedDeparture, let estimated = estimatedDeparture else { return nil }
        return Int(estimated.timeIntervalSince(planned))
    }
}

struct Journey: Identifiable {
    let id: String
    let legs: [Leg]

    var departure: Date? { legs.first?.departure }
    var arrival: Date? { legs.last?.arrival }
    var transitLegs: [Leg] { legs.filter { !$0.mode.isWalking } }

    var duration: TimeInterval? {
        guard let departure, let arrival else { return nil }
        return arrival.timeIntervalSince(departure)
    }

    /// The leg being travelled — or waited for — at `date`: the first one not yet
    /// finished. Nil once the journey is over.
    func activeLeg(at date: Date) -> Leg? {
        legs.first { ($0.arrival ?? .distantFuture) > date }
    }

    static func list(from dto: TripDTO) -> [Journey] {
        (dto.journeys ?? []).compactMap { journey in
            let legs = (journey.legs ?? []).map(Leg.init(dto:))
            guard !legs.isEmpty else { return nil }
            return Journey(id: legs.map(\.id).joined(separator: "|"), legs: legs)
        }
    }
}

private extension CLLocationCoordinate2D {
    /// TfNSW sends `[latitude, longitude]`, the opposite order to GeoJSON. Getting this
    /// backwards puts the whole route in the Indian Ocean.
    init?(pair: [Double]) {
        guard pair.count == 2 else { return nil }
        self.init(latitude: pair[0], longitude: pair[1])
    }
}

extension Leg {
    init(dto: LegDTO) {
        let transportation = dto.transportation
        let mode = TransitMode(productClass: transportation?.product?.productClass)
        // `disassembledName` first. `number` is the long form — the Metro sends
        // "M1 Metro North West & Bankstown Line" there and "M1" here, and only the short
        // one fits a route badge.
        let route = transportation?.disassembledName ?? transportation?.number
        let originName = dto.origin?.disassembledName ?? dto.origin?.name ?? ""
        let planned = dto.origin?.departureTimePlanned
        let plannedKey = planned.map { String(Int($0.timeIntervalSince1970)) } ?? "?"

        self.init(
            id: "\(mode)|\(route ?? "")|\(originName)|\(plannedKey)",
            mode: mode,
            route: route,
            headsign: transportation?.destination?.name,
            originName: originName,
            destinationName: dto.destination?.disassembledName ?? dto.destination?.name ?? "",
            plannedDeparture: planned,
            estimatedDeparture: dto.origin?.departureTimeEstimated,
            plannedArrival: dto.destination?.arrivalTimePlanned,
            estimatedArrival: dto.destination?.arrivalTimeEstimated,
            hasRealtime: dto.isRealtimeControlled ?? false,
            path: (dto.coords ?? []).compactMap(CLLocationCoordinate2D.init(pair:)),
            stops: (dto.stopSequence ?? []).compactMap(LegStop.init(dto:)),
            durationSeconds: dto.duration
        )
    }
}

extension LegStop {
    init?(dto: PlaceDTO) {
        guard let coordinate = dto.coord.flatMap(CLLocationCoordinate2D.init(pair:)) else { return nil }
        self.init(
            id: dto.id ?? UUID().uuidString,
            name: dto.disassembledName ?? dto.name ?? "",
            coordinate: coordinate,
            departure: dto.departureTimeEstimated ?? dto.departureTimePlanned
        )
    }
}
