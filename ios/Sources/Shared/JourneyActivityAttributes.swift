import ActivityKit
import Foundation

/// The stage of the journey the activity is narrating. Each phase pairs a verb with
/// `ContentState.place`: Board X, Alight at X, Walk to X, Arrived at X.
enum JourneyActivityPhase: String, Codable {
    case waiting, riding, walking, arrived
}

/// Live Activity payload for a real journey.
///
/// Everything counts down from fixed Dates rather than carrying "minutes left", so the
/// Lock Screen ticks by itself between updates via `Text(timerInterval:)` and an update
/// is only worth sending when a fact actually changed. iOS 26 silently drops content
/// states over 4 KB; this one measures ~450 bytes worst case, and the controller still
/// checks on every send.
struct JourneyActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: JourneyActivityPhase
        var mode: TransitMode
        /// "T1" / "333". Nil for walking legs, which have no route to badge.
        var routeBadge: String?
        /// Lock Screen and expanded island only — the small slots have no room for it.
        var headsign: String?
        /// The noun the phase's verb applies to: origin stop while waiting, alight stop
        /// while riding, walk destination while walking, journey destination on arrival.
        var place: String
        /// Fixed anchors, never derived from "now". A now-based field would make every
        /// derivation unique and turn the app's 1-second tick into an update storm.
        var countdownStart: Date
        var countdownEnd: Date
        var status: DepartureStatus
        /// Pre-formatted in Australia/Sydney. The widget would render a Date in the
        /// device timezone, and the app promises Sydney times everywhere.
        var arrivalShort: String
        /// 1-based over all legs, walks included — matches the in-app leg list.
        var legIndex: Int
        var legCount: Int
        /// "Then T1 · 5:12 pm" — the connection that matters while walking or waiting.
        var nextLegLine: String?
        /// Station progress, riding phase only; nil elsewhere and for legs without a
        /// usable stop sequence. `stopIndex` is the 1-based count of stops already
        /// passed — it moves in whole stops, never continuously.
        var stopIndex: Int? = nil
        var stopCount: Int? = nil
        var nextStopName: String? = nil
        /// Intermediate stops' positions inside countdownStart...countdownEnd as 0–1
        /// fractions, 3-dp quantized: the bar's tick marks, honest about uneven gaps.
        /// Real fractions cost ~6 bytes a stop; equal spacing would misdraw every
        /// express pattern for the sake of bytes nobody needs back.
        var stopFractions: [Double]? = nil
    }

    /// Only the destination, on purpose: a replan that swaps journeys to the same place
    /// updates the running activity in place instead of flashing end-and-restart.
    var destinationName: String
    var startedAt: Date
}
