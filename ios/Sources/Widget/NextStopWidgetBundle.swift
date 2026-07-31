import SwiftUI
import WidgetKit

@main
struct NextStopWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpikeLiveActivity()
        JourneyLiveActivity()
    }
}
