import SwiftUI

/// The user's position: a dot with a compass cone behind it. The cone widens as compass
/// confidence drops — a wide wedge honestly says "roughly that way" — and hides entirely
/// when the reading is unusable, because a wrong direction is worse than none.
struct UserPuckView: View {
    /// Screen-space rotation (device heading minus camera heading), pre-unwrapped by the
    /// caller so successive values animate the short way around. Nil hides the cone.
    let rotation: Double?
    let apertureDegrees: Double?

    var body: some View {
        ZStack {
            if let rotation, let apertureDegrees {
                HeadingCone(apertureDegrees: apertureDegrees)
                    .fill(
                        RadialGradient(
                            colors: [Theme.Colors.userPuck.opacity(0.55), .clear],
                            center: .center, startRadius: 4, endRadius: 55
                        )
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(rotation))
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
            Circle()
                .fill(Theme.Colors.userPuck)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        }
        .animation(.smooth(duration: 0.3), value: rotation)
        .animation(.smooth(duration: 0.3), value: apertureDegrees)
    }
}

/// A wedge pointing up — north until rotated — centred on the puck.
struct HeadingCone: Shape {
    var apertureDegrees: Double

    var animatableData: Double {
        get { apertureDegrees }
        set { apertureDegrees = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let half = Angle.degrees(apertureDegrees / 2)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center, radius: radius,
            startAngle: .degrees(-90) - half, endAngle: .degrees(-90) + half,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
