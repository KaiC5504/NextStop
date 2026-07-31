import Foundation

enum TfNSWError: Error, Equatable {
    case missingKey
    case unauthorised
    case http(Int)
    case transport
}

struct StopSuggestion: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let isBest: Bool
}

protocol HTTPFetching {
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPFetching {
    /// Not `data(for:)` directly: the real method is `data(for:delegate:)`, whose full name
    /// differs, so it would not satisfy a `data(for:)` requirement.
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

struct TfNSWClient {
    private static let base = URL(string: "https://api.transport.nsw.gov.au/v1/tp/")!

    private let session: HTTPFetching
    private let keyProvider: () -> String?

    init(session: HTTPFetching = URLSession.shared, keyProvider: @escaping () -> String? = KeychainStore.read) {
        self.session = session
        self.keyProvider = keyProvider
    }

    func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard let key = keyProvider(), !key.isEmpty else { throw TfNSWError.missingKey }

        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "outputFormat", value: "rapidJSON"),
            URLQueryItem(name: "coordOutputFormat", value: "EPSG:4326"),
        ] + query

        var request = URLRequest(url: components.url!)
        request.setValue("apikey \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    /// The types default to "any", not "stop". `findStops` searches with `type_sf=any` and
    /// returns POIs, suburbs and addresses alongside stops — sending one of those ids as a
    /// "stop" resolves to nothing and the API returns zero journeys rather than an error.
    /// "any" resolves every id kind, stops included.
    func journeys(
        originID: String,
        originType: String = "any",
        destinationID: String,
        destinationType: String = "any",
        time: PlanTime
    ) async throws -> [Journey] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: time.date)

        let request = try makeRequest(path: "trip", query: [
            URLQueryItem(name: "depArrMacro", value: time.macro),
            URLQueryItem(name: "itdDate", value: String(format: "%04d%02d%02d", parts.year!, parts.month!, parts.day!)),
            URLQueryItem(name: "itdTime", value: String(format: "%02d%02d", parts.hour!, parts.minute!)),
            URLQueryItem(name: "type_origin", value: originType),
            URLQueryItem(name: "name_origin", value: originID),
            URLQueryItem(name: "type_destination", value: destinationType),
            URLQueryItem(name: "name_destination", value: destinationID),
            // The EFA default is whatever the server feels like; six covers the option
            // list without paying for journeys nobody scrolls to.
            URLQueryItem(name: "calcNumberOfTrips", value: "6"),
            URLQueryItem(name: "TfNSWTR", value: "true"),
        ])

        let dto: TripDTO = try await send(request)
        return Journey.list(from: dto)
    }

    func findStops(matching query: String) async throws -> [StopSuggestion] {
        let request = try makeRequest(path: "stop_finder", query: [
            URLQueryItem(name: "type_sf", value: "any"),
            URLQueryItem(name: "name_sf", value: query),
            URLQueryItem(name: "anyMaxSizeHitList", value: "12"),
        ])

        let dto: StopFinderDTO = try await send(request)
        return (dto.locations ?? [])
            .compactMap { location -> (StopSuggestion, Int)? in
                guard let id = location.id,
                      let name = location.disassembledName ?? location.name else { return nil }
                return (
                    StopSuggestion(id: id, name: name, isBest: location.isBest ?? false),
                    location.matchQuality ?? 0
                )
            }
            .sorted { left, right in
                if left.0.isBest != right.0.isBest { return left.0.isBest }
                return left.1 > right.1
            }
            .map(\.0)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.fetch(request)
        } catch {
            throw TfNSWError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw TfNSWError.transport }
        // 401 and 403 both mean the key is wrong or unsubscribed, and both need the user
        // sent to Settings rather than shown a retry button.
        if http.statusCode == 401 || http.statusCode == 403 { throw TfNSWError.unauthorised }
        guard http.statusCode == 200 else { throw TfNSWError.http(http.statusCode) }

        do {
            return try JSONDecoder.tfnswDecoder.decode(T.self, from: data)
        } catch {
            throw TfNSWError.transport
        }
    }
}
