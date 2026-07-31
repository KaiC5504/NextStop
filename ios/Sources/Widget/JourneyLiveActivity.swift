import ActivityKit
import SwiftUI
import WidgetKit

/// Wires the shared journey presentation views into a Live Activity. Thin on purpose,
/// like the spike configuration: everything visual lives in `JourneyActivityViews.swift`
/// so the in-app harness renders exactly what ships here rather than a copy that drifts.
struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            JourneyLockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Theme.Colors.background.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    JourneyExpandedLeadingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    JourneyExpandedTrailingView(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    JourneyExpandedBottomView(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                JourneyCompactLeadingView(state: context.state)
            } compactTrailing: {
                JourneyCompactTrailingView(state: context.state, isStale: context.isStale)
            } minimal: {
                JourneyMinimalView(state: context.state)
            }
        }
    }
}
