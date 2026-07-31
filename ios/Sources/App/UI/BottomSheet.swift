import SwiftUI

enum SheetDetent: Equatable {
    case peek, medium
}

/// The drag maths, pure and tested. UIScrollView's constants, because the hand already
/// knows how iOS momentum is supposed to feel.
enum SheetPhysics {
    /// Where a released drag would coast to: UIKit's projection formula at the `.fast`
    /// deceleration rate — a sheet should settle briskly, not sail.
    static func projectedEnd(position: CGFloat, velocity: CGFloat) -> CGFloat {
        let rate: CGFloat = 0.99
        return position + velocity / 1000 * rate / (1 - rate)
    }

    static func nearestDetent(peek: CGFloat, medium: CGFloat, projectedHeight: CGFloat) -> SheetDetent {
        abs(projectedHeight - peek) < abs(projectedHeight - medium) ? .peek : .medium
    }

    /// Logarithmic resistance past the ends, asymptotic to `dimension` so no fling can
    /// drag the sheet arbitrarily far off its detents.
    static func rubberBand(overshoot: CGFloat, dimension: CGFloat = 300) -> CGFloat {
        guard overshoot > 0 else { return 0 }
        let c: CGFloat = 0.55
        return (1 - 1 / (overshoot * c / dimension + 1)) * dimension
    }
}

/// A floating glass sheet with two snap points: `peek` shows the handle and the peek
/// content, `medium` reveals the rest. Custom rather than `.presentationDetents`
/// because the peek content holds a NavigationLink that must push on the root stack,
/// Settings already presents as a real sheet above this screen, and the snap physics
/// should match the app's spring.
struct BottomSheet<Peek: View, More: View>: View {
    @Binding var detent: SheetDetent
    @ViewBuilder let peek: () -> Peek
    @ViewBuilder let more: () -> More

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var peekHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private static var spring: Animation { .spring(response: 0.38, dampingFraction: 0.82) }

    var body: some View {
        content
            // Natural size regardless of the clamped frame below, so the measurements
            // reflect what the content wants, not what it was given.
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { fullHeight = $0 })
            .frame(height: fullHeight == 0 ? nil : displayHeight, alignment: .top)
            .frame(maxWidth: .infinity)
            .clipped()
            .glassSurface()
            .padding(.horizontal, Theme.Spacing.s)
            .gesture(drag)
            .animation(Self.spring, value: detent)
            // Direct 1:1 tracking during the drag; the spring takes over on release,
            // which also makes a mid-flight grab interruptible.
            .animation(dragTranslation == 0 ? Self.spring : nil, value: dragTranslation)
    }

    private var content: some View {
        VStack(spacing: 0) {
            VStack(spacing: Theme.Spacing.m) {
                Capsule()
                    .fill(Theme.Colors.stroke)
                    .frame(width: 36, height: 5)
                    .padding(.top, Theme.Spacing.s)
                peek()
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.m)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { peekHeight = $0 })

            more()
                .padding(.bottom, Theme.Spacing.m)
        }
    }

    private var targetHeight: CGFloat { detent == .peek ? peekHeight : fullHeight }

    private var displayHeight: CGFloat {
        let raw = targetHeight - dragTranslation
        if raw > fullHeight {
            return fullHeight + SheetPhysics.rubberBand(overshoot: raw - fullHeight)
        }
        if raw < peekHeight {
            return max(peekHeight - SheetPhysics.rubberBand(overshoot: peekHeight - raw), 0)
        }
        return raw
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let projected = targetHeight - SheetPhysics.projectedEnd(
                    position: value.translation.height,
                    velocity: value.velocity.height
                )
                detent = SheetPhysics.nearestDetent(
                    peek: peekHeight, medium: fullHeight, projectedHeight: projected
                )
            }
    }
}
