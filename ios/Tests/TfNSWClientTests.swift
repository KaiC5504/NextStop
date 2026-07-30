import XCTest
@testable import NextStop

struct StubFetcher: HTTPFetching {
    var status: Int = 200
    var payload: Data = Data()
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (payload, response)
    }
}

final class TfNSWClientTests: XCTestCase {
    func testRequestCarriesTheApiKeyAndRapidJSON() throws {
        let client = TfNSWClient(session: StubFetcher(), keyProvider: { "secret" })
        let request = try client.makeRequest(path: "trip", query: [URLQueryItem(name: "a", value: "b")])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "apikey secret")
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://api.transport.nsw.gov.au/v1/tp/trip"))
        XCTAssertTrue(url.contains("outputFormat=rapidJSON"))
        XCTAssertTrue(url.contains("coordOutputFormat=EPSG:4326") || url.contains("coordOutputFormat=EPSG%3A4326"))
    }

    /// A coordinate origin needs type_origin=coord; sending it with the default "stop"
    /// fails on device only, after a Codemagic build and a TestFlight install.
    func testOriginTypeIsSentAsGiven() async throws {
        let client = TfNSWClient(session: StubFetcher(payload: Fixture.data("trip-sample")), keyProvider: { "k" })
        let request = try client.makeRequest(path: "trip", query: [
            URLQueryItem(name: "type_origin", value: "coord"),
            URLQueryItem(name: "name_origin", value: "151.180400:-33.796900:EPSG:4326"),
        ])
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.contains("type_origin=coord"))
    }

    func testMissingKeyIsItsOwnError() async {
        let client = TfNSWClient(session: StubFetcher(), keyProvider: { nil })
        do {
            _ = try await client.journeys(originID: "1", destinationID: "2", departing: Date())
            XCTFail("expected missingKey")
        } catch let error as TfNSWError {
            XCTAssertEqual(error, .missingKey)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testUnauthorisedIsDistinctFromOtherFailures() async {
        let client = TfNSWClient(session: StubFetcher(status: 401), keyProvider: { "bad" })
        do {
            _ = try await client.journeys(originID: "1", destinationID: "2", departing: Date())
            XCTFail("expected unauthorised")
        } catch let error as TfNSWError {
            XCTAssertEqual(error, .unauthorised)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testJourneysDecodeFromAStubbedResponse() async throws {
        let client = TfNSWClient(
            session: StubFetcher(payload: Fixture.data("trip-sample")), keyProvider: { "k" }
        )
        let journeys = try await client.journeys(originID: "1", destinationID: "2", departing: Date())
        XCTAssertFalse(journeys.isEmpty)
        XCTAssertFalse(journeys[0].legs.isEmpty)
    }

    func testStopSuggestionsAreRankedBestFirst() async throws {
        let client = TfNSWClient(
            session: StubFetcher(payload: Fixture.data("stopfinder-sample")), keyProvider: { "k" }
        )
        let stops = try await client.findStops(matching: "Chatswood")
        XCTAssertFalse(stops.isEmpty)
        if let firstBest = stops.firstIndex(where: { $0.isBest }) {
            XCTAssertEqual(firstBest, 0, "the API's own best match must sort first")
        }
        XCTAssertFalse(stops.contains { $0.name.isEmpty })
    }
}
