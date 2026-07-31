import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationProvider
    @Environment(\.openURL) private var openURL
    @Binding var showingSettings: Bool
    // CI screenshots the expanded search with `-initialScreen search`; there is no other
    // way to look at it before a device build exists.
    @State private var searchExpanded = UserDefaults.standard.string(forKey: "initialScreen") == "search"
    @State private var bottomContentHeight: CGFloat = 0
    @State private var sheetDetent: SheetDetent = .medium

    var body: some View {
        ZStack(alignment: .top) {
            JourneyMapView(journey: model.selectedJourney, bottomInset: bottomContentHeight)

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

            VStack(spacing: Theme.Spacing.s) {
                topControls
                if locationDenied && !searchExpanded {
                    locationDeniedBanner
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            bottomCard
        }
        .animation(.snappy, value: locationDenied)
        .sensoryFeedback(.success, trigger: model.phase) { _, new in new == .ready }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var locationDenied: Bool {
        location.authorisation == .denied || location.authorisation == .restricted
    }

    /// The fallback origin is deliberate — a journey from the wrong place is visible and
    /// correctable — but only if the user is told it is happening.
    private var locationDeniedBanner: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "location.slash.fill")
                .foregroundStyle(Theme.Colors.late)
            VStack(alignment: .leading, spacing: 2) {
                Text("Location is off")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Journeys start from Chatswood Station")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.s)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(Theme.Spacing.m)
        .glassSurface(cornerRadius: Theme.Radius.pill)
        .padding(.horizontal, Theme.Spacing.m)
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
        VStack(spacing: 0) {
            Spacer()
            if hasBottomContent {
                // Status above options: the peek detent shows the summary, dragging up
                // reveals the alternatives beneath it.
                BottomSheet(detent: $sheetDetent) {
                    statusContent
                } more: {
                    if !model.journeys.isEmpty {
                        JourneyOptionsView()
                    }
                }
                // Measured so the map's recenter button rides above the sheet, drag
                // included.
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    bottomContentHeight = height
                }
            }
        }
        .padding(.bottom, Theme.Spacing.s)
        .onChange(of: hasBottomContent) { _, has in
            if !has { bottomContentHeight = 0 }
        }
        .onChange(of: model.journeys.isEmpty) { _, empty in
            if !empty { sheetDetent = .medium }
        }
    }

    private var hasBottomContent: Bool {
        hasStatus || !model.journeys.isEmpty
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
                            if model.plannedFromFallback {
                                Text("From Chatswood Station — no location fix")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Colors.late)
                            }
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
