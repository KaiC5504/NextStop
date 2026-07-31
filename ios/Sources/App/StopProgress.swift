import Foundation

/// Where along a stop sequence a ride is at a moment in time. Callers pass plain Dates
/// (already chosen between estimated and planned) in timetable order.
enum StopProgress {
    /// Continuous position in stop-index space: 0 at the first stop, count − 1 at the
    /// last, linear in between. Drives the in-app spine fill only — the Live Activity
    /// must use `passedCount`, which moves in whole stops, or every tick becomes an
    /// ActivityKit update.
    static func position(times: [Date], now: Date) -> Double {
        guard let first = times.first, let last = times.last else { return 0 }
        guard now > first else { return 0 }
        guard now < last else { return Double(times.count - 1) }
        let index = times.lastIndex { $0 <= now } ?? 0
        let start = times[index]
        let span = times[index + 1].timeIntervalSince(start)
        return Double(index) + now.timeIntervalSince(start) / span
    }

    /// Stops already reached. Discrete on purpose — see `position`.
    static func passedCount(times: [Date], now: Date) -> Int {
        times.filter { $0 <= now }.count
    }

    /// Stop times mapped into `start...end` as 0–1 fractions for the progress bar's
    /// tick marks. Quantized to 3 decimals so the encoded payload stays small and equal
    /// inputs encode equal; clamped just inside the ends so no tick hides under the
    /// bar's end caps; duplicates collapsed by requiring strict ascent.
    static func tickFractions(times: [Date], start: Date, end: Date) -> [Double] {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return [] }
        var fractions: [Double] = []
        for time in times {
            let clamped = min(max(time.timeIntervalSince(start) / span, 0.001), 0.999)
            let quantized = (clamped * 1000).rounded() / 1000
            if quantized > (fractions.last ?? 0) {
                fractions.append(quantized)
            }
        }
        return fractions
    }

    /// Fill fraction for the expanded station list's spine. The boarding stop isn't
    /// rendered (it's the row's "from X"), so the spine runs from the first shown dot's
    /// centre to the alighting dot's: position 1 → 0, position stopCount − 1 → 1.
    static func spineFillFraction(position: Double, stopCount: Int) -> Double {
        guard stopCount > 2 else {
            return position >= Double(max(stopCount - 1, 1)) ? 1 : 0
        }
        return min(max((position - 1) / Double(stopCount - 2), 0), 1)
    }
}
