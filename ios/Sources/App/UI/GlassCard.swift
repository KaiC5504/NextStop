import SwiftUI

/// Read once — it is a launch argument, not something that changes mid-run.
private let legacyGlass = UserDefaults.standard.bool(forKey: "legacyGlass")

extension View {
    /// iOS 26 Liquid Glass by default — the look this app always wanted. CI launches
    /// with `-legacyGlass YES` because the simulator renders glassEffect inconsistently
    /// and screenshots are the only pre-device check; TestFlight builds get the real
    /// thing. The manual stroke and shadow only exist on the legacy path — glass brings
    /// its own edge treatment.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        if legacyGlass {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.Colors.stroke, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        } else {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
