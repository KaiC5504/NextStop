import SwiftUI

enum SheetDetent: Equatable {
    case peek, medium, large
}

/// The drag maths, pure and tested. UIScrollView's constants, because the hand already
/// knows how iOS momentum is supposed to feel.
enum SheetPhysics {
    /// The one spring every sheet motion uses — gesture release, the hosts'
    /// programmatic detent writes, and the recenter button riding between insets.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    /// Glass drawn past the content's bottom edge: covers the home-indicator area at
    /// rest and backs any upward rubber-band overshoot (the band is asymptotic to it).
    /// Lives here because generic types can't hold static stored properties.
    static let topSlack: CGFloat = 80

    /// Where a released drag would coast to: UIKit's projection formula at the `.fast`
    /// deceleration rate — a sheet should settle briskly, not sail.
    static func projectedEnd(position: CGFloat, velocity: CGFloat) -> CGFloat {
        let rate: CGFloat = 0.99
        return position + velocity / 1000 * rate / (1 - rate)
    }

    /// `DragGesture(minimumDistance:)` reports translation from touch-down, so the
    /// first update arrives already 8pt in. Subtracting the activation distance keeps
    /// the card under the finger instead of popping ahead of it.
    static func effectiveTranslation(_ raw: CGFloat, activation: CGFloat = 8) -> CGFloat {
        guard abs(raw) > activation else { return 0 }
        return raw - (raw < 0 ? -activation : activation)
    }

    /// Ties resolve toward the smaller detent (strict `<` keeps the first candidate).
    /// A short-content sheet measures medium == large; that candidate drops out so the
    /// sheet settles at `.large` and releases the scroll lock — `.medium` would name
    /// the same height and leave the list permanently unscrollable.
    static func nearestDetent(peek: CGFloat, medium: CGFloat, large: CGFloat, projectedHeight: CGFloat) -> SheetDetent {
        var candidates: [(SheetDetent, CGFloat)] = [(.peek, peek), (.large, large)]
        if medium < large { candidates.insert((.medium, medium), at: 1) }
        return candidates.min { abs(projectedHeight - $0.1) < abs(projectedHeight - $1.1) }!.0
    }

    /// Logarithmic resistance past the ends, asymptotic to `dimension` so no fling can
    /// drag the sheet arbitrarily far off its detents.
    static func rubberBand(overshoot: CGFloat, dimension: CGFloat = 300) -> CGFloat {
        guard overshoot > 0 else { return 0 }
        let c: CGFloat = 0.55
        return (1 - 1 / (overshoot * c / dimension + 1)) * dimension
    }

    /// The sheet height a drag in flight should show: target minus translation,
    /// rubber-banded below peek and above full. The upward band's dimension is the
    /// card's hidden slack, so overshoot can never outrun the glass behind it.
    static func visibleHeight(
        target: CGFloat, translation: CGFloat,
        peek: CGFloat, full: CGFloat, topSlack: CGFloat
    ) -> CGFloat {
        let raw = target - translation
        if raw > full {
            return full + rubberBand(overshoot: raw - full, dimension: topSlack)
        }
        if raw < peek {
            return max(peek - rubberBand(overshoot: peek - raw), 0)
        }
        return raw
    }
}

/// A glass sheet with three snap points: `peek` shows the handle and the peek content,
/// `medium` reveals the top of the rest, `large` all of it. Custom rather than
/// `.presentationDetents` because the peek content holds a NavigationLink that must push
/// on the root stack, Settings already presents as a real sheet above this screen, and
/// the snap physics should match the app's spring.
///
/// The card is laid out once at its full height and slid with `.offset` — a drag is a
/// pure render transform. Resizing per touch event re-ran layout for the whole subtree
/// and re-rendered the glass at new bounds over a live map; that was the drag ghosting.
struct BottomSheet<Peek: View, More: View>: View {
    @Binding var detent: SheetDetent
    /// How much of the `more` region the medium detent shows.
    var mediumReveal: CGFloat = 260
    /// The resting visible height — reported on detent changes and measurement, never
    /// per drag frame. Hosts feed it to the map inset so the recenter button rides
    /// detents, not the finger.
    var onRestingHeight: ((CGFloat) -> Void)? = nil
    /// True from first drag movement to release, so hosts can pause per-second work
    /// that would invalidate this subtree mid-drag.
    var onDragChanged: ((Bool) -> Void)? = nil
    @ViewBuilder let peek: () -> Peek
    @ViewBuilder let more: () -> More

    @Environment(\.scenePhase) private var scenePhase
    /// Plain @State, not @GestureState: the release animation is explicit in onEnded,
    /// and a cancelled gesture is reset by the scenePhase hook below.
    @State private var dragTranslation: CGFloat = 0
    @State private var peekHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    var body: some View {
        content
            // Natural size, not the proposed one: a greedy ScrollView would otherwise
            // inflate to its maxHeight cap and "full" would stop meaning "content".
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                fullHeight = height
                publishResting()
            }
            .padding(.bottom, SheetPhysics.topSlack)
            .frame(maxWidth: .infinity)
            .glassSurface()
            .padding(.horizontal, Theme.Spacing.s)
            .offset(y: cardOffset)
            // The first frame has no measurements yet; a zero offset would flash the
            // whole card fully open for one layout pass.
            .opacity(fullHeight == 0 ? 0 : 1)
            .gesture(drag)
            .animation(SheetPhysics.spring, value: detent)
            .onChange(of: detent) { _, _ in publishResting() }
            .onChange(of: scenePhase) { _, _ in
                // Gesture cancellation (incoming call, app switcher) never delivers
                // onEnded; without this the sheet would strand mid-drag.
                if dragTranslation != 0 {
                    dragTranslation = 0
                    onDragChanged?(false)
                }
            }
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
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                peekHeight = height
                publishResting()
            }

            more()
                .padding(.bottom, Theme.Spacing.m)
        }
    }

    private var mediumHeight: CGFloat { min(fullHeight, peekHeight + mediumReveal) }

    private var targetHeight: CGFloat {
        switch detent {
        case .peek: peekHeight
        case .medium: mediumHeight
        case .large: fullHeight
        }
    }

    private var visibleHeight: CGFloat {
        SheetPhysics.visibleHeight(
            target: targetHeight,
            translation: SheetPhysics.effectiveTranslation(dragTranslation),
            peek: peekHeight, full: fullHeight, topSlack: SheetPhysics.topSlack
        )
    }

    /// How far to slide the card down from its laid-out position (bottom-anchored by
    /// the host) so exactly `visibleHeight` of content stays on screen. The slack keeps
    /// glass past the bottom edge for any overshoot the rubber band allows.
    private var cardOffset: CGFloat {
        fullHeight == 0 ? 0 : SheetPhysics.topSlack + fullHeight - visibleHeight
    }

    private func publishResting() { onRestingHeight?(targetHeight) }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragTranslation == 0 { onDragChanged?(true) }
                dragTranslation = value.translation.height
            }
            .onEnded { value in
                let projected = targetHeight - SheetPhysics.projectedEnd(
                    position: SheetPhysics.effectiveTranslation(value.translation.height),
                    velocity: value.velocity.height
                )
                let landing = SheetPhysics.nearestDetent(
                    peek: peekHeight, medium: mediumHeight, large: fullHeight,
                    projectedHeight: projected
                )
                // The only animation in the sheet: explicit, on release, covering both
                // the translation collapse and any detent change in one spring.
                withAnimation(SheetPhysics.spring) {
                    dragTranslation = 0
                    detent = landing
                }
                onDragChanged?(false)
            }
    }
}
