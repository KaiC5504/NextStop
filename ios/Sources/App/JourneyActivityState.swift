import Foundation

/// Derives the Live Activity content for a journey at a point in time.
///
/// Pure on purpose: this runs every UI tick, and the controller only sends when the
/// result changes — so equal inputs must produce equal states. Nothing in here may read
/// the clock; `now` and `startedAt` arrive as arguments.
enum JourneyActivityState {
    /// How early the waiting-phase progress bar starts filling. Anchoring to the leg's
    /// departure rather than the activity start keeps a bar begun hours ahead from
    /// sitting visibly frozen.
    private static let waitingWindow: TimeInterval = 45 * 60

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: "Australia/Sydney")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func make(
        journey: Journey,
        destinationName: String,
        startedAt: Date,
        now: Date
    ) -> JourneyActivityAttributes.ContentState? {
        guard !journey.legs.isEmpty else { return nil }
        let legCount = journey.legs.count
        let arrivalShort = journey.arrival.map(clock.string(from:)) ?? "—"
        // Stable stand-in for the times TfNSW occasionally omits. Anchored to the
        // activity start, never to `now`, or stability across ticks is lost.
        let fallback = startedAt.addingTimeInterval(600)

        guard let index = journey.legs.firstIndex(where: { ($0.arrival ?? .distantFuture) > now }) else {
            let last = journey.legs[legCount - 1]
            let end = last.arrival ?? fallback
            return state(
                phase: .arrived, leg: last, routeBadge: nil, headsign: nil,
                place: destinationName,
                start: last.departure ?? startedAt, end: end,
                status: DepartureStatus(leg: last), arrivalShort: arrivalShort,
                legIndex: legCount, legCount: legCount, nextLegLine: nil
            )
        }

        let leg = journey.legs[index]
        let nextTransit = journey.legs[(index + 1)...].first { !$0.mode.isWalking }

        if leg.mode.isWalking {
            // The actionable fact while walking is the connection, not the walk: borrow
            // the next transit leg's status so a delayed train shows before boarding it.
            return state(
                phase: .walking, leg: leg, routeBadge: nil, headsign: nil,
                place: leg.destinationName,
                start: leg.departure ?? startedAt, end: leg.arrival ?? fallback,
                status: nextTransit.map(DepartureStatus.init(leg:)) ?? .scheduledOnly,
                arrivalShort: arrivalShort,
                legIndex: index + 1, legCount: legCount,
                nextLegLine: nextLegLine(for: nextTransit)
            )
        } else if let departure = leg.departure, now < departure {
            return state(
                phase: .waiting, leg: leg, routeBadge: leg.route, headsign: leg.headsign,
                place: leg.originName,
                start: max(startedAt, departure.addingTimeInterval(-waitingWindow)),
                end: departure,
                status: DepartureStatus(leg: leg), arrivalShort: arrivalShort,
                legIndex: index + 1, legCount: legCount,
                nextLegLine: nextLegLine(for: nextTransit)
            )
        } else {
            return state(
                phase: .riding, leg: leg, routeBadge: leg.route, headsign: leg.headsign,
                place: leg.destinationName,
                start: leg.departure ?? startedAt, end: leg.arrival ?? fallback,
                status: DepartureStatus(leg: leg), arrivalShort: arrivalShort,
                legIndex: index + 1, legCount: legCount, nextLegLine: nil
            )
        }
    }

    /// `Text(timerInterval:)` traps on a range whose start exceeds its end, and replans
    /// can produce degenerate leg times — so the range is normalised in one place.
    private static func state(
        phase: JourneyActivityPhase, leg: Leg, routeBadge: String?, headsign: String?,
        place: String, start: Date, end: Date, status: DepartureStatus,
        arrivalShort: String, legIndex: Int, legCount: Int, nextLegLine: String?
    ) -> JourneyActivityAttributes.ContentState {
        JourneyActivityAttributes.ContentState(
            phase: phase, mode: leg.mode, routeBadge: routeBadge, headsign: headsign,
            place: place, countdownStart: min(start, end), countdownEnd: end,
            status: status, arrivalShort: arrivalShort,
            legIndex: legIndex, legCount: legCount, nextLegLine: nextLegLine
        )
    }

    private static func nextLegLine(for leg: Leg?) -> String? {
        guard let leg, let departure = leg.departure else { return nil }
        return "Then \(leg.route ?? leg.mode.displayName) · \(clock.string(from: departure))"
    }
}
