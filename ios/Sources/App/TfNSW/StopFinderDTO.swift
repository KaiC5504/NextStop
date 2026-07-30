import Foundation

struct StopFinderDTO: Decodable {
    let locations: [LocationDTO]?
}

struct LocationDTO: Decodable {
    let id: String?
    let name: String?
    let disassembledName: String?
    let isBest: Bool?
    let matchQuality: Int?
}
