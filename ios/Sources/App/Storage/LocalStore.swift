import Foundation

/// One JSON file in Documents. Not SwiftData: this holds tens of rows of personal data with
/// no relationships and no queries, and a model container would be more moving parts than
/// the whole feature.
final class LocalStore: ObservableObject {
    private struct Contents: Codable {
        var recents: [StopSuggestion] = []
        var saved: [StopSuggestion] = []
        var feedback: [PredictionFeedback] = []
    }

    private static let recentsLimit = 10

    static let shared = LocalStore(
        fileURL: FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nextstop-store.json")
    )

    private let fileURL: URL
    private var contents: Contents { didSet { publish(); persist() } }

    @Published private(set) var recents: [StopSuggestion] = []
    @Published private(set) var saved: [StopSuggestion] = []
    @Published private(set) var feedback: [PredictionFeedback] = []
    /// Derived rather than held in the journey screen's `@State`: navigating back to the map
    /// and returning rebuilds that view, which would offer the buttons again on legs already
    /// rated and let the same leg be filed twice.
    @Published private(set) var ratedLegIDs: Set<String> = []

    init(fileURL: URL) {
        self.fileURL = fileURL
        // A corrupt or absent file starts empty rather than throwing. Losing a recents list
        // is not worth refusing to launch over. `didSet` does not fire in init, so this
        // load does not immediately write back.
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder.tfnswDecoder.decode(Contents.self, from: $0) }
        self.contents = loaded ?? Contents()
        publish()
    }

    func addRecent(_ stop: StopSuggestion) {
        var next = contents.recents.filter { $0.id != stop.id }
        next.insert(stop, at: 0)
        contents.recents = Array(next.prefix(Self.recentsLimit))
    }

    func toggleSaved(_ stop: StopSuggestion) {
        if let index = contents.saved.firstIndex(where: { $0.id == stop.id }) {
            contents.saved.remove(at: index)
        } else {
            contents.saved.append(stop)
        }
    }

    func isSaved(_ stop: StopSuggestion) -> Bool {
        contents.saved.contains { $0.id == stop.id }
    }

    func record(_ item: PredictionFeedback) {
        contents.feedback.append(item)
    }

    func exportFeedbackJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(contents.feedback)
    }

    private func publish() {
        recents = contents.recents
        saved = contents.saved
        feedback = contents.feedback
        ratedLegIDs = Set(contents.feedback.compactMap(\.legID))
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(contents) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
