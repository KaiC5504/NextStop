import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle, planning, ready
        /// The request succeeded and returned nothing. Distinct from `.ready` because an
        /// empty journey list renders identically to the idle screen — which is exactly how
        /// a POI destination silently did nothing at all.
        case noService
        case failed(TfNSWError)
    }

    /// Below this the Stop Finder returns most of Sydney and the list is useless.
    private static let minimumQueryLength = 3

    let store: LocalStore
    let location = LocationProvider()
    private let client: TfNSWClient

    @Published var destination: StopSuggestion?
    @Published var journeys: [Journey] = []
    @Published var selectedJourneyID: String?
    @Published var searchResults: [StopSuggestion] = []
    @Published var searchError: TfNSWError?
    @Published var phase: Phase = .idle

    private var departAt: Date?

    init(client: TfNSWClient = TfNSWClient(), store: LocalStore = .shared) {
        self.client = client
        self.store = store
    }

    var selectedJourney: Journey? {
        journeys.first { $0.id == selectedJourneyID }
    }

    /// Chatswood Station, confirmed against stop_finder. Falling back to a fixed origin
    /// rather than refusing to plan: a journey from the wrong place is visible and
    /// correctable, a blank screen tells the user nothing.
    static let fallbackOriginID = "206710"

    var originID: String {
        location.coordinate.map(LocationProvider.tfnswOriginString(for:)) ?? Self.fallbackOriginID
    }

    var originType: String {
        location.coordinate == nil ? "stop" : "coord"
    }

    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= Self.minimumQueryLength else {
            searchResults = []
            searchError = nil
            return
        }
        do {
            searchResults = try await client.findStops(matching: query)
            searchError = nil
        } catch let error as TfNSWError {
            searchResults = []
            searchError = error
        } catch {
            searchResults = []
            searchError = .transport
        }
    }

    /// Clears the search without touching `phase`, so dismissing the field cannot wipe the
    /// banner explaining why the last plan failed.
    func clearSearch() {
        searchResults = []
        searchError = nil
    }

    func plan(to stop: StopSuggestion) async {
        destination = stop
        departAt = Date()
        selectedJourneyID = nil
        phase = .planning
        await load(recordRecent: true)
    }

    /// Re-plans against the pinned departure time, keeping the user's selected option if it
    /// is still in the result. Called on a timer while the journey screen is open.
    func refresh() async {
        guard destination != nil else { return }
        await load(recordRecent: false)
    }

    func reset() {
        destination = nil
        journeys = []
        selectedJourneyID = nil
        searchResults = []
        searchError = nil
        departAt = nil
        phase = .idle
    }

    private func load(recordRecent: Bool) async {
        guard let destination, let departAt else { return }
        do {
            let found = try await client.journeys(
                originID: originID,
                originType: originType,
                destinationID: destination.id,
                departing: departAt
            )
            journeys = found
            if selectedJourneyID == nil || !found.contains(where: { $0.id == selectedJourneyID }) {
                selectedJourneyID = found.first?.id
            }
            if recordRecent { store.addRecent(destination) }
            phase = found.isEmpty ? .noService : .ready
        } catch let error as TfNSWError {
            journeys = []
            selectedJourneyID = nil
            phase = .failed(error)
        } catch {
            journeys = []
            selectedJourneyID = nil
            phase = .failed(.transport)
        }
    }
}
