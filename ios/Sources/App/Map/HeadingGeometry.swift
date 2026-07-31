import Foundation

/// Pure angle math for the user puck. Separated from the views because a sign error here
/// looks correct at north-up — the only state the simulator can show — and wrong
/// everywhere else. The tests are the safety net.
enum HeadingGeometry {
    /// Where the cone should point on screen: device heading relative to whatever the
    /// camera has rotated to. Both arguments in degrees clockwise from north.
    static func screenRotation(deviceHeading: Double, cameraHeading: Double) -> Double {
        normalize(deviceHeading - cameraHeading)
    }

    /// Shortest-path unwrap: animating 359° → 1° must rotate 2° clockwise, not 358° the
    /// other way. Returns an angle equivalent to `target` chosen within ±180° of
    /// `current`, so SwiftUI's rotation animation takes the short way.
    static func continuousRotation(from current: Double, to target: Double) -> Double {
        let delta = normalize(target - current + 180) - 180
        return current + delta
    }

    /// Cone width from compass confidence, clamped so it neither narrows into a laser
    /// nor widens into a meaningless disc. Nil in, nil out: no reading, no cone.
    static func apertureDegrees(forAccuracy accuracy: Double?) -> Double? {
        guard let accuracy, accuracy >= 0 else { return nil }
        return min(max(accuracy * 2, 20), 90)
    }

    private static func normalize(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }
}
