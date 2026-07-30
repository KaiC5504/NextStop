import SwiftUI

struct SearchSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.searchError {
                    Section {
                        Text(error == .missingKey || error == .unauthorised
                             ? "Add a valid Transport NSW API key in Settings."
                             : "Could not reach Transport NSW.")
                            .font(.footnote)
                            .foregroundStyle(Theme.Colors.late)
                    }
                }
                if !store.saved.isEmpty && text.isEmpty {
                    Section("Saved") { rows(store.saved) }
                }
                if !store.recents.isEmpty && text.isEmpty {
                    Section("Recent") { rows(store.recents) }
                }
                if !model.searchResults.isEmpty {
                    Section("Results") { rows(model.searchResults) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Where to?")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $text, prompt: "Station, stop, or address")
            .onChange(of: text) { _, new in schedule(new) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func rows(_ stops: [StopSuggestion]) -> some View {
        ForEach(stops) { stop in
            Button {
                dismiss()
                Task { await model.plan(to: stop) }
            } label: {
                HStack {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.Colors.textSecondary)
                    Text(stop.name).foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    if store.isSaved(stop) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
            }
            .swipeActions(edge: .leading) {
                Button(store.isSaved(stop) ? "Unsave" : "Save") { store.toggleSaved(stop) }
                    .tint(.yellow)
            }
        }
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
