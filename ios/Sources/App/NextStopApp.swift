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
    // CI launches the simulator with `-initialTab layouts` to screenshot a specific
    // screen. Without a provisioned device there is no other way to look at these
    // layouts at all. UserDefaults picks launch arguments up via NSArgumentDomain.
    @State private var selection = UserDefaults.standard.string(forKey: "initialTab") ?? "spike"

    var body: some View {
        TabView(selection: $selection) {
            SpikeControlView()
                .tabItem { Label("Spike", systemImage: "waveform.path.ecg") }
                .tag("spike")
            ActivityHarnessView()
                .tabItem { Label("Layouts", systemImage: "rectangle.on.rectangle") }
                .tag("layouts")
            DebugLogView()
                .tabItem { Label("Log", systemImage: "doc.text") }
                .tag("log")
        }
    }
}
