import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: LocalStore
    @Environment(\.dismiss) private var dismiss

    @State private var key = ""
    @State private var hasKey = KeychainStore.read() != nil
    @State private var exported: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Paste your key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        try? KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                        hasKey = KeychainStore.read() != nil
                        key = ""
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if hasKey {
                        Label("A key is stored on this device", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.Colors.onTime)
                    }
                } header: {
                    Text("Transport NSW API key")
                } footer: {
                    Text("Free from opendata.transport.nsw.gov.au. Stored in the iOS Keychain and sent only to Transport NSW.")
                }

                Section("Feedback") {
                    LabeledContent("Recorded", value: "\(store.feedback.count)")
                    if let exported {
                        ShareLink("Export as JSON", item: exported)
                    }
                }

                Section("Developer") {
                    NavigationLink("Live Activity spike") { SpikeControlView() }
                    NavigationLink("Live Activity layouts") { ActivityHarnessView() }
                    NavigationLink("Debug log") { DebugLogView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: writeExport)
        }
        .preferredColorScheme(.dark)
    }

    /// ShareLink needs a file that already exists, so the export is written when the screen
    /// appears rather than when the user taps.
    private func writeExport() {
        guard !store.feedback.isEmpty, let data = try? store.exportFeedbackJSON() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nextstop-feedback.json")
        try? data.write(to: url, options: .atomic)
        exported = url
    }
}
