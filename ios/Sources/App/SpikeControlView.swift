import Combine
import SwiftUI

struct SpikeControlView: View {
    @Environment(SpikeSession.self) private var session

    // Elapsed and fix-age are computed from Date() rather than stored, so nothing would
    // invalidate this view between ticks. Writing to this on a timer is what redraws it.
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var session = session

        NavigationStack {
            Form {
                if SpikeLog.shared.usingFallbackLocation {
                    Section {
                        Label(
                            "App Group unavailable — logging to Documents instead. "
                            + "The entitlement is misconfigured and the widget cannot "
                            + "share state either.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                        .font(.footnote)
                    }
                }

                Section("Result") {
                    LabeledContent("Verdict") {
                        Text(session.verdict)
                            .font(.headline)
                            .foregroundStyle(verdictColour)
                    }
                    LabeledContent("Max gap") {
                        Text(String(format: "%.1fs", session.maxGap))
                            .monospacedDigit()
                            .foregroundStyle(verdictColour)
                    }
                    LabeledContent("Ticks", value: "\(session.tick)")
                    LabeledContent("Elapsed", value: session.elapsed.shortDuration)
                    LabeledContent("Last fix") {
                        Text(session.fixAge.map { $0.shortDuration + " ago" } ?? "none")
                            .foregroundStyle(session.fixAge == nil ? .secondary : .primary)
                    }
                }

                Section("Mechanism under test") {
                    Picker("Mechanism", selection: $session.mechanism) {
                        ForEach(HoldMechanism.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(session.isRunning)

                    Text(session.mechanism.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tick interval") {
                    Picker("Interval", selection: $session.interval) {
                        Text("1s").tag(TimeInterval(1))
                        Text("5s").tag(TimeInterval(5))
                        Text("15s").tag(TimeInterval(15))
                    }
                    .pickerStyle(.segmented)
                    .disabled(session.isRunning)
                }

                Section {
                    Button(session.isRunning ? "Stop" : "Start") {
                        if session.isRunning {
                            Task { await session.stop() }
                        } else {
                            session.start()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(session.isRunning ? .red : .accentColor)
                } footer: {
                    Text(
                        "Start, lock the phone, put it in your pocket, ride to USyd. "
                        + "The Lock Screen shows the max gap, so you can read the result "
                        + "without unlocking."
                    )
                }
            }
            .navigationTitle("Live Activity spike")
            .onReceive(clock) { now = $0 }
        }
    }

    private var verdictColour: Color {
        guard session.tick > 0 else { return .secondary }
        return session.maxGap <= SpikeAttributes.ContentState.gapBudget ? .green : .red
    }
}
