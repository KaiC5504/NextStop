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
    private let journeyActivity = JourneyActivityController()
    private let alightAlerts: AlightAlertScheduler
    /// Set the first time the live journey screen opens for the current destination —
    /// that tap is the commitment signal that starts the Live Activity. Also the fixed
    /// anchor the state deriver needs to stay stable across ticks.
    private var activityStartedAt: Date?

    @Published var destination: StopSuggestion?
    @Published var journeys: [Journey] = []
    @Published var selectedJourneyID: String? {
        didSet {
            // Switching routes moves the alighting stops. Only a real journey re-syncs:
            // the selection also goes nil mid-replan and on failure, and a failed replan
            // in a tunnel must not tear down alerts that would have fired locally —
            // reset/arrival/destination-change own the teardown.
            guard activityStartedAt != nil, oldValue != selectedJourneyID,
                  let journey = selectedJourney else { return }
            Task { await alightAlerts.sync(journey: journey, now: Date()) }
        }
    }
    @Published var searchResults: [StopSuggestion] = []
    @Published var searchError: TfNSWError?
    @Published var phase: Phase = .idle
    /// True when the shown journeys start at the Chatswood fallback rather than the
    /// user. The fallback is deliberate; hiding it from the user would not be.
    @Published private(set) var plannedFromFallback = false

    @Published private(set) var planTimeSelection: PlanTimeSelection = .leaveNow
    /// Resolved once per plan so refreshes re-ask the same question; see
    /// `PlanTimeSelection.resolved(now:)`.
    private var resolvedPlanTime: PlanTime?

    /// Demo models are pre-loaded fakes for CI screenshots: no network refresh, no
    /// ActivityKit, no permission prompts — a dialog or a failed request would sit over
    /// every screenshot taken after it.
    let isDemo: Bool

    init(
        client: TfNSWClient = TfNSWClient(), store: LocalStore = .shared, isDemo: Bool = false,
        // nil rather than a default instance: a default argument is evaluated in the
        // caller's context, where the scheduler's MainActor init is out of reach.
        alightAlerts: AlightAlertScheduler? = nil
    ) {
        self.client = client
        self.store = store
        self.isDemo = isDemo
        self.alightAlerts = alightAlerts ?? AlightAlertScheduler()
        if !isDemo {
            Task { await journeyActivity.sweepOrphans() }
            // Notifications get the same treatment as activities: anything pending at
            // launch was armed by a previous life the terminate hook never saw.
            Task { await self.alightAlerts.sweepOrphansAtLaunch() }
        }
    }

    var selectedJourney: Journey? {
        journeys.first { $0.id == selectedJourneyID }
    }

    /// True from the journey commitment until arrival or teardown — the window during
    /// which the app holds background location so the activity can die with a force-quit.
    var isJourneyActive: Bool { activityStartedAt != nil }

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
        // A new destination invalidates the running activity. Same-destination replans
        // update it in place instead — that path never comes through here.
        if let current = destination, current.id != stop.id {
            activityStartedAt = nil
            alightAlerts.cancelAll()
            location.setBackgroundHold(false)
            await journeyActivity.end()
        }
        destination = stop
        resolvedPlanTime = planTimeSelection.resolved(now: Date())
        selectedJourneyID = nil
        phase = .planning
        location.set(fidelity: .navigation)
        await load(recordRecent: true)
    }

    /// Re-plans against the pinned departure time, keeping the user's selected option if it
    /// is still in the result. Called on a timer while the journey screen is open.
    func refresh() async {
        guard !isDemo, destination != nil else { return }
        await load(recordRecent: false)
    }

    func reset() {
        activityStartedAt = nil
        alightAlerts.cancelAll()
        Task { await journeyActivity.end() }
        location.setBackgroundHold(false)
        location.set(fidelity: .ambient)
        destination = nil
        journeys = []
        selectedJourneyID = nil
        searchResults = []
        searchError = nil
        planTimeSelection = .leaveNow
        resolvedPlanTime = nil
        phase = .idle
        plannedFromFallback = false
    }

    /// Re-plans with a new trip time. No-op on the time control before a destination is
    /// chosen — the selection is stored and the next plan resolves it.
    func setPlanTime(_ selection: PlanTimeSelection) async {
        planTimeSelection = selection
        guard destination != nil else { return }
        resolvedPlanTime = selection.resolved(now: Date())
        phase = .planning
        await load(recordRecent: false)
    }

    private func load(recordRecent: Bool) async {
        guard let destination, let time = resolvedPlanTime else { return }
        let usedFallback = location.coordinate == nil
        do {
            let found = try await client.journeys(
                originID: originID,
                originType: originType,
                destinationID: destination.id,
                time: time
            )
            journeys = found
            if selectedJourneyID == nil || !found.contains(where: { $0.id == selectedJourneyID }) {
                selectedJourneyID = found.first?.id
            }
            if recordRecent { store.addRecent(destination) }
            plannedFromFallback = usedFallback
            phase = found.isEmpty ? .noService : .ready
            // Only on success: a transient failure mid-tunnel must not tear down the
            // locally scheduled alerts — firing from the last good estimate is the point.
            if activityStartedAt != nil {
                await alightAlerts.sync(journey: selectedJourney, now: Date())
            }
        } catch let error as TfNSWError {
            journeys = []
            selectedJourneyID = nil
            phase = .failed(error)
        } catch {
            journeys = []
            selectedJourneyID = nil
            phase = .failed(.transport)
        }
        syncJourneyActivity(now: Date())
    }

    func startJourneyActivity() {
        guard !isDemo, destination != nil, let journey = selectedJourney else { return }
        if activityStartedAt == nil {
            activityStartedAt = Date()
            // The commitment moment doubles as the one contextual place to ask for
            // notification permission.
            Task { await alightAlerts.begin(journey: journey, now: Date()) }
            // Re-opening the screen after arrival re-raises this transiently; the next
            // tick derives .arrived and drops it again.
            location.setBackgroundHold(true)
        }
        syncJourneyActivity(now: Date())
    }

    /// Called every second while the journey screen ticks. Cheap by design: the
    /// derivation is pure, and the controller only talks to ActivityKit when the
    /// derived state actually changed.
    func syncJourneyActivity(now: Date) {
        guard let startedAt = activityStartedAt,
              let destination,
              let journey = selectedJourney,
              let state = JourneyActivityState.make(
                  journey: journey, destinationName: destination.name,
                  startedAt: startedAt, now: now
              )
        else { return }
        if state.phase == .arrived {
            // The journey is over: drop the anchor so ticks stop deriving, and the
            // background hold with it. `startedAt` is already captured above.
            activityStartedAt = nil
            location.setBackgroundHold(false)
            location.set(fidelity: .ambient)
        }
        Task {
            if state.phase == .arrived {
                alightAlerts.cancelAll()
                await journeyActivity.endArrived(finalState: state)
            } else {
                await journeyActivity.sync(state: state, destinationName: destination.name, startedAt: startedAt)
            }
        }
    }
}
