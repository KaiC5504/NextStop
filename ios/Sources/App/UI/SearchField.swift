import SwiftUI

/// A magnifying glass that morphs into a full-width search bar, with results hanging below
/// it. One capsule whose width animates rather than two views swapped by a transition —
/// swapping makes the glass blur pop, which is the one thing a morph has to get right.
struct SearchField: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: LocalStore
    @Binding var isExpanded: Bool

    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var searchTask: Task<Void, Never>?

    private static let collapsedSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            bar
            if isExpanded {
                results
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var bar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: Self.collapsedSize, height: Self.collapsedSize)
                .contentShape(Circle())
                .onTapGesture { expand() }

            if isExpanded {
                TextField("Station, stop, or address", text: $text)
                    .focused($focused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .onChange(of: text) { _, new in schedule(new) }

                Button {
                    collapse()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(9)
                        .background(Circle().fill(Theme.Colors.stroke))
                }
                .padding(.trailing, Theme.Spacing.s)
            }
        }
        .frame(maxWidth: isExpanded ? .infinity : Self.collapsedSize, alignment: .leading)
        .frame(height: Self.collapsedSize)
        .glassSurface(cornerRadius: Self.collapsedSize / 2)
    }

    @ViewBuilder
    private var results: some View {
        let sections = visibleSections
        if !sections.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        Text(section.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.top, Theme.Spacing.s)
                            .padding(.horizontal, Theme.Spacing.m)
                        ForEach(section.stops) { stop in
                            row(stop)
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.s)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 360)
            .glassSurface(cornerRadius: Theme.Radius.pill)
        } else if let error = model.searchError {
            Text(error == .missingKey || error == .unauthorised
                 ? "Add a valid Transport NSW API key in Settings."
                 : "Could not reach Transport NSW.")
                .font(.footnote)
                .foregroundStyle(Theme.Colors.late)
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: Theme.Radius.pill)
        }
    }

    private struct Section {
        let title: String
        let stops: [StopSuggestion]
    }

    private var visibleSections: [Section] {
        if !model.searchResults.isEmpty {
            return [Section(title: "Results", stops: model.searchResults)]
        }
        guard text.isEmpty else { return [] }
        return [
            Section(title: "Saved", stops: store.saved),
            Section(title: "Recent", stops: store.recents),
        ].filter { !$0.stops.isEmpty }
    }

    private func row(_ stop: StopSuggestion) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                choose(stop)
            } label: {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(stop.name)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // A visible star rather than a swipe action: swipeActions only does anything
            // inside a List, and this list is a ScrollView so it can live inside the glass.
            Button {
                withAnimation(.snappy) { store.toggleSaved(stop) }
            } label: {
                Image(systemName: store.isSaved(stop) ? "star.fill" : "star")
                    .foregroundStyle(store.isSaved(stop) ? .yellow : Theme.Colors.textSecondary)
                    .padding(.leading, Theme.Spacing.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
    }

    private func expand() {
        guard !isExpanded else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { isExpanded = true }
        focused = true
    }

    private func collapse() {
        searchTask?.cancel()
        focused = false
        text = ""
        model.clearSearch()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { isExpanded = false }
    }

    private func choose(_ stop: StopSuggestion) {
        collapse()
        Task { await model.plan(to: stop) }
    }

    /// Debounced rather than fired per keystroke: the quota is 60k calls a day and a
    /// nine-letter station name would otherwise spend nine of them.
    private func schedule(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
    }
}
