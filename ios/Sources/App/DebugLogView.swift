import SwiftUI

/// Reads the spike log back on the device.
///
/// There is no Mac to attach a debugger to, so this screen and the share sheet are the
/// only way the result of a commute ever leaves the phone.
struct DebugLogView: View {
    @State private var lines: [String] = []
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            Group {
                if lines.isEmpty {
                    ContentUnavailableView(
                        "No log yet",
                        systemImage: "doc.text",
                        description: Text("Start a run on the Spike tab.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(colour(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .textSelection(.enabled)
                        .padding(10)
                    }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Refresh", systemImage: "arrow.clockwise", action: reload)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: SpikeLog.shared.fileURL).disabled(lines.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Text("\(lines.count) lines · \(SpikeLog.shared.sizeDescription) · newest first")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear", role: .destructive) { confirmingClear = true }
                            .disabled(lines.isEmpty)
                    }
                }
            }
            .confirmationDialog("Delete the log?", isPresented: $confirmingClear) {
                Button("Delete", role: .destructive) {
                    SpikeLog.shared.clear()
                    lines = []
                }
            } message: {
                Text("Share it first if this run mattered — it cannot be recovered.")
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        let parsed = SpikeLog.shared.read()
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        lines = Array(parsed.reversed())
    }

    /// The two lines worth spotting in four hundred: a missed tick and anything failing.
    private func colour(for line: String) -> Color {
        if line.contains("\tgap\t") { return .orange }
        if line.contains("failed") || line.contains("denied") || line.contains("error") {
            return .red
        }
        if line.contains("session.") || line.contains("activity.") { return .blue }
        return .primary
    }
}
