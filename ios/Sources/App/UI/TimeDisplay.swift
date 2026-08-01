import Foundation

/// The one place the itinerary UI formats minutes and clock times. Two rules the rest of
/// the app must not re-derive: minutes round to nearest (a 9:50 walk is "10 min", not the
/// truncated "9"), and a missing value hides the label instead of rendering "0 min".
enum TimeDisplay {
    /// Journey times are Sydney times regardless of the device's timezone.
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: "Australia/Sydney")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func durationLabel(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return "\(max(1, Int((Double(seconds) / 60).rounded()))) min"
    }

    /// "4:27 – 5:10 am": a shared meridiem collapses; "11:58 am – 12:20 pm" keeps both.
    static func clockRange(from: Date, to: Date) -> String {
        var lhs = clock.string(from: from)
        let rhs = clock.string(from: to)
        for meridiem in [" am", " pm"] where lhs.hasSuffix(meridiem) && rhs.hasSuffix(meridiem) {
            lhs = String(lhs.dropLast(meridiem.count))
        }
        return "\(lhs) – \(rhs)"
    }

    /// The route row's big number: "43 min" below the hour, "1 hr" / "1 hr 15 min" above.
    static func longDurationLabel(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        guard minutes >= 60 else { return "\(minutes) min" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(rest) min"
    }

    /// Bare minutes for the sequence line's walk glyph: "5". Nil hides it like the others.
    static func walkBadgeMinutes(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return "\(max(1, Int((Double(seconds) / 60).rounded())))"
    }

    /// "in 14 min" while the leg is ahead, "now" around its start, nil once it is more
    /// than a minute gone — the countdown the leg list has always shown, but labeled so
    /// it can no longer be misread as a duration.
    static func countdownLabel(to date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        guard seconds >= -60 else { return nil }
        let minutes = Int((seconds / 60).rounded())
        return minutes <= 0 ? "now" : "in \(minutes) min"
    }
}
