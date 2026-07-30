import SwiftUI

extension View {
    /// Material rather than iOS 26's `glassEffect`: the CI simulator has rendered glass
    /// inconsistently, and the screenshots are the only way to see this UI before a device
    /// build exists. Revisit once there is a phone to compare against.
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }
}

struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Capsule()
                .fill(Theme.Colors.stroke)
                .frame(width: 36, height: 5)
            content
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .glassSurface()
        .padding(.horizontal, Theme.Spacing.s)
    }
}
