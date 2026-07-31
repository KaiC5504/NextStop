import Foundation

struct PredictionFeedback: Codable, Identifiable {
    let id: UUID
    /// Optional so records written before this field existed still decode. A decode failure
    /// here empties the whole store, which would cost the user their saved places too.
    var legID: String? = nil
    let recordedAt: Date
    let wasCorrect: Bool
    let mode: String
    let route: String?
    let originName: String
    let destinationName: String
    let plannedDeparture: Date?
    let estimatedDeparture: Date?
    let hadRealtime: Bool
    /// Tap time minus the time the app predicted. Positive means the app was early.
    let errorSeconds: Int?
}

extension PredictionFeedback {
    init(leg: Leg, wasCorrect: Bool, tappedAt: Date) {
        self.init(
            id: UUID(),
            legID: leg.id,
            recordedAt: tappedAt,
            wasCorrect: wasCorrect,
            mode: leg.mode.displayName,
            route: leg.route,
            originName: leg.originName,
            destinationName: leg.destinationName,
            plannedDeparture: leg.plannedDeparture,
            estimatedDeparture: leg.estimatedDeparture,
            hadRealtime: leg.hasRealtime,
            errorSeconds: leg.departure.map { Int(tappedAt.timeIntervalSince($0)) }
        )
    }
}
