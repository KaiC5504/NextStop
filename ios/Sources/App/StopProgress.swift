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

    /// Physical fill height for the expanded station list's spine. The boarding stop
    /// isn't rendered (it's the row's "from X"), so the spine runs dot centre to dot
    /// centre over stopCount − 1 shown dots — every segment `rowHeight` tall except the
    /// last, which spans into the taller alighting row: (rowHeight + finalRowHeight) / 2.
    /// Position 1 → 0, position stopCount − 1 → the full track height.
    static func spineFillHeight(
        position: Double, stopCount: Int, rowHeight: Double, finalRowHeight: Double
    ) -> Double {
        let segments = stopCount - 2
        guard segments >= 1 else { return 0 }
        var remaining = min(max(position - 1, 0), Double(segments))
        var height = 0.0
        for index in 0..<segments {
            let length = index == segments - 1 ? (rowHeight + finalRowHeight) / 2 : rowHeight
            if remaining >= 1 {
                height += length
                remaining -= 1
            } else {
                height += remaining * length
                break
            }
        }
        return height
    }
}
