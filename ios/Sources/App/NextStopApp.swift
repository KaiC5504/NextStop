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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @State private var showingSettings: Bool
    private let requestedScreen: String?

    init() {
        // CI launches with `-initialScreen <name>` to screenshot a screen it cannot
        // otherwise reach. UserDefaults picks launch arguments up via NSArgumentDomain.
        // Passing the argument at all also suppresses the first-run sheet: a fresh
        // simulator never has a key, so `-initialScreen home` would otherwise photograph
        // Settings sitting on top of the screen it was asked for.
        let requested = UserDefaults.standard.string(forKey: "initialScreen")
        requestedScreen = requested
        // The options, journey and medium-detent screens need journeys to show, and CI
        // has no API key. "medium" falls through to the Home branch at its default
        // detent — the only way to photograph the sheet's resting medium geometry.
        let demoScreens = ["options", "journey", "medium"]
        _model = StateObject(
            wrappedValue: requested.map(demoScreens.contains) == true ? .demo() : AppModel()
        )
        let firstRun = requested == nil && KeychainStore.read() == nil
        _showingSettings = State(initialValue: requested == "settings" || firstRun)
    }

    var body: some View {
        if requestedScreen == "layouts" {
            // Straight to the Live Activity harness: CI cannot navigate Settings →
            // Developer, and this screen is the only pre-device look at the layouts.
            ActivityHarnessView()
                .preferredColorScheme(.dark)
        } else if requestedScreen == "journey" {
            NavigationStack {
                LiveJourneyView()
                    .background(Theme.Colors.background)
            }
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.location)
            .preferredColorScheme(.dark)
            .tint(Theme.Colors.textPrimary)
        } else {
            NavigationStack {
                HomeView(showingSettings: $showingSettings)
                    .background(Theme.Colors.background)
            }
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.location)
            .preferredColorScheme(.dark)
            .tint(Theme.Colors.textPrimary)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(model)
                    .environmentObject(model.store)
                    .environment(session)
            }
            // The root owns the location stream. When HomeView owned it, pushing the
            // live journey screen fired its onDisappear and froze the dot mid-journey.
            .onAppear {
                // CI launches (-initialScreen) cannot tap a permission dialog, and a
                // screenshot of the alert is a wasted run — simctl grants instead.
                if requestedScreen == nil {
                    model.location.requestWhenInUse()
                }
                model.location.start()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: model.location.start()
                case .background: model.location.stop()
                default: break
                }
            }
        }
    }
}
