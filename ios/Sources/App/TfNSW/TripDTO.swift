import Foundation

struct TripDTO: Decodable {
    let journeys: [JourneyDTO]?
}

struct JourneyDTO: Decodable {
    let legs: [LegDTO]?
}

struct LegDTO: Decodable {
    let duration: Int?
    let coords: [[Double]]?
    let origin: PlaceDTO?
    let destination: PlaceDTO?
    let transportation: TransportationDTO?
    let isRealtimeControlled: Bool?
    let stopSequence: [PlaceDTO]?
}

struct PlaceDTO: Decodable {
    let id: String?
    let name: String?
    let disassembledName: String?
    let coord: [Double]?
    let departureTimePlanned: Date?
    let departureTimeEstimated: Date?
    let arrivalTimePlanned: Date?
    let arrivalTimeEstimated: Date?
}

struct TransportationDTO: Decodable {
    let number: String?
    let disassembledName: String?
    let product: ProductDTO?
    let destination: NamedDTO?
}

struct ProductDTO: Decodable {
    let productClass: Int?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case productClass = "class"
        case name
    }
}

struct NamedDTO: Decodable {
    let name: String?
}

extension JSONDecoder {
    /// Every field on these DTOs is optional on purpose. The Trip Planner omits keys rather
    /// than sending nulls, and it omits different ones depending on mode, time of day, and
    /// whether a service is realtime-tracked. One missing key must never cost the whole
    /// journey.
    static var tfnswDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
