import SwiftUI

@main
struct NextStopApp: App {
    @State private var session = SpikeSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
        .onChange(of: scenePhase) { _, phase in
            // The transition into background is the moment the experiment actually
            // begins, and the transition that never arrives back is the failure.
            session.noteScenePhase(String(describing: phase))
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            SpikeControlView()
                .tabItem { Label("Spike", systemImage: "waveform.path.ecg") }
            ActivityHarnessView()
                .tabItem { Label("Layouts", systemImage: "rectangle.on.rectangle") }
            DebugLogView()
                .tabItem { Label("Log", systemImage: "doc.text") }
        }
    }
}
