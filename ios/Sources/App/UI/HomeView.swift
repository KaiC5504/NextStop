import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showingSettings: Bool
    // CI screenshots the expanded search with `-initialScreen search`; there is no other
    // way to look at it before a device build exists.
    @State private var searchExpanded = UserDefaults.standard.string(forKey: "initialScreen") == "search"

    var body: some View {
        ZStack(alignment: .top) {
            JourneyMapView(journey: model.selectedJourney)
                .ignoresSafeArea()

            // Tapping the map closes the search rather than leaving it hanging open over
            // the route the user is trying to look at.
            if searchExpanded {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            searchExpanded = false
                        }
                    }
            }

            topControls
            bottomCard
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            model.location.requestWhenInUse()
            model.location.start()
        }
        .onDisappear { model.location.stop() }
    }

    private var topControls: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            SearchField(isExpanded: $searchExpanded)

            if !searchExpanded {
                // Without this the row sizes to its content and the ZStack centres it,
                // leaving both controls floating in the middle of the map.
                Spacer(minLength: Theme.Spacing.s)
                if model.destination != nil {
                    circleButton("xmark") {
                        withAnimation(.snappy) { model.reset() }
                    }
                }
                circleButton("gearshape") { showingSettings = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 44, height: 44)
                .glassSurface(cornerRadius: 22)
        }
    }

    @ViewBuilder
    private var bottomCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer()
            if !model.journeys.isEmpty {
                JourneyOptionsView()
            }
            if hasStatus {
                GlassCard { statusContent }
            }
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    private var hasStatus: Bool {
        switch model.phase {
        case .idle: false
        case .ready: model.destination != nil && model.selectedJourney != nil
        default: true
        }
    }

    /// Nothing at all when idle: the map is the screen, and an empty card telling the user
    /// there is nothing to say only takes space away from it.
    @ViewBuilder
    private var statusContent: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .planning:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView().tint(Theme.Colors.textSecondary)
                Text("Finding a way there…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        case .ready:
            if let destination = model.destination, model.selectedJourney != nil {
                NavigationLink {
                    LiveJourneyView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("To \(destination.name)")
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Text("Tap for live times")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        case .noService:
            message("No services to \(model.destination?.name ?? "there") right now", tint: Theme.Colors.noRealtime)
        case .failed(let error):
            errorRow(error)
        }
    }

    private func message(_ text: String, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.circle")
            Text(text).font(.footnote)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
    }

    @ViewBuilder
    private func errorRow(_ error: TfNSWError) -> some View {
        let text: String = switch error {
        case .missingKey: "Add your Transport NSW API key in Settings"
        case .unauthorised: "That API key was rejected. Check it in Settings."
        case .http(let code): "Transport NSW returned an error (\(code))"
        case .transport: "Could not reach Transport NSW"
        }
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(.footnote)
            Spacer(minLength: 0)
            if error == .missingKey || error == .unauthorised {
                Button("Settings") { showingSettings = true }.font(.footnote.weight(.semibold))
            }
        }
        .foregroundStyle(Theme.Colors.late)
    }
}
