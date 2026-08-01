import SwiftUI

/// The user's position, Google style: a blue disc with a bold white arrow rotating
/// with the compass. No reading, no arrow — the plain disc stays, because a wrong
/// direction is worse than none.
struct UserPuckView: View {
    /// Screen-space rotation (device heading minus camera heading), pre-unwrapped by the
    /// caller so successive values animate the short way around. Nil hides the arrow.
    let rotation: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.userPuck)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
            if let rotation {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotation))
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: rotation)
    }
}
