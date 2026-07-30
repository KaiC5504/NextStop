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
    @Environment(SpikeSession.self) private var session
    @StateObject private var model = AppModel()
    @State private var showingSettings: Bool

    init() {
        // CI launches with `-initialScreen <name>` to screenshot a screen it cannot
        // otherwise reach. UserDefaults picks launch arguments up via NSArgumentDomain.
        // Passing the argument at all also suppresses the first-run sheet: a fresh
        // simulator never has a key, so `-initialScreen home` would otherwise photograph
        // Settings sitting on top of the screen it was asked for.
        let requested = UserDefaults.standard.string(forKey: "initialScreen")
        let firstRun = requested == nil && KeychainStore.read() == nil
        _showingSettings = State(initialValue: requested == "settings" || firstRun)
    }

    var body: some View {
        NavigationStack {
            HomeView(showingSettings: $showingSettings)
                .background(Theme.Colors.background)
        }
        .environmentObject(model)
        .environmentObject(model.store)
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.textPrimary)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.store)
                .environment(session)
        }
    }
}
