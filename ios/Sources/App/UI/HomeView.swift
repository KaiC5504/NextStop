import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showingSettings: Bool
    @State private var showingSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            JourneyMapView(journey: model.selectedJourney)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.m) {
                if !model.journeys.isEmpty {
                    JourneyOptionsView()
                }
                GlassCard {
                    if let destination = model.destination, model.selectedJourney != nil {
                        NavigationLink {
                            LiveJourneyView()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("To \(destination.name)")
                                        .font(.headline)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text("Tap for live times")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    } else {
                        Button { showingSearch = true } label: {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("Where to?")
                                Spacer()
                            }
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.vertical, Theme.Spacing.s)
                        }
                    }

                    if case .planning = model.phase {
                        ProgressView().tint(Theme.Colors.textSecondary)
                    }
                    if case .failed(let error) = model.phase {
                        errorRow(error)
                    }
                }
            }
            .padding(.bottom, Theme.Spacing.s)
        }
        // Without an inline title the map sits under an empty large-title bar, which reads
        // as an unfinished screen in the CI screenshot.
        .navigationTitle("NextStop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
            ToolbarItem(placement: .topBarLeading) {
                if model.destination != nil {
                    Button("Clear") { withAnimation(.snappy) { model.reset() } }
                }
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchSheet()
                .environmentObject(model)
                .environmentObject(model.store)
        }
        .onAppear {
            model.location.requestWhenInUse()
            model.location.start()
        }
        .onDisappear { model.location.stop() }
    }

    @ViewBuilder
    private func errorRow(_ error: TfNSWError) -> some View {
        let message: String = switch error {
        case .missingKey: "Add your Transport NSW API key in Settings"
        case .unauthorised: "That API key was rejected. Check it in Settings."
        case .http(let code): "Transport NSW returned an error (\(code))"
        case .transport: "Could not reach Transport NSW"
        }
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.footnote)
            Spacer()
            if error == .missingKey || error == .unauthorised {
                Button("Settings") { showingSettings = true }.font(.footnote.weight(.semibold))
            }
        }
        .foregroundStyle(Theme.Colors.late)
    }
}
