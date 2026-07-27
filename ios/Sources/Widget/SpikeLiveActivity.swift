import ActivityKit
import SwiftUI
import WidgetKit

/// Wires the shared presentation views into a Live Activity.
///
/// Deliberately thin: everything visual lives in `SpikeActivityViews.swift` so the app's
/// harness screen renders exactly what ships here rather than a copy that drifts.
struct SpikeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpikeAttributes.self) { context in
            SpikeLockScreenView(state: context.state)
                .activityBackgroundTint(.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpikeExpandedLeadingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SpikeExpandedTrailingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SpikeExpandedBottomView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "tram.fill")
            } compactTrailing: {
                SpikeCompactTrailingView(state: context.state)
            } minimal: {
                SpikeMinimalView(state: context.state)
            }
        }
    }
}
