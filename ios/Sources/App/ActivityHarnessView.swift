import SwiftUI

/// Renders every Live Activity presentation at roughly its real size against mock state.
///
/// Xcode previews are unavailable when the build machine is remote, so this is how the
/// layouts get iterated: change the shared views, ship a build, look at the phone. It
/// also makes the failure styling visible without having to actually fail a commute.
struct ActivityHarnessView: View {
    @State private var tick = 128
    @State private var maxGap: TimeInterval = 4.2
    @State private var hasFix = true

    private var state: SpikeAttributes.ContentState {
        let now = Date()
        return SpikeAttributes.ContentState(
            tick: tick,
            updatedAt: now,
            startedAt: now.addingTimeInterval(-Double(tick) * 5),
            mechanism: "CLBackgroundActivitySession",
            fixAge: hasFix ? 8 : nil,
            maxGap: maxGap
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    controls

                    presentation("Lock Screen", height: 92) {
                        SpikeLockScreenView(state: state)
                    }

                    presentation("Dynamic Island — expanded", height: 116) {
                        VStack(spacing: 10) {
                            HStack(alignment: .top) {
                                SpikeExpandedLeadingView(state: state)
                                Spacer()
                                SpikeExpandedTrailingView(state: state)
                            }
                            SpikeExpandedBottomView(state: state)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    HStack(spacing: 16) {
                        presentation("Compact", height: 40, width: 180) {
                            HStack(spacing: 6) {
                                Image(systemName: "tram.fill").font(.caption)
                                Spacer(minLength: 0)
                                SpikeCompactTrailingView(state: state).font(.caption)
                            }
                            .padding(.horizontal, 14)
                        }

                        presentation("Minimal", height: 40, width: 60) {
                            SpikeMinimalView(state: state).font(.caption)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Location fix available", isOn: $hasFix)
            VStack(alignment: .leading) {
                Text("Max gap \(String(format: "%.1f", maxGap))s — threshold is \(Int(SpikeAttributes.ContentState.gapBudget))s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Slider(value: $maxGap, in: 0...60)
            }
            Stepper("Tick \(tick)", value: $tick, in: 0...9999, step: 8)
                .font(.footnote)
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func presentation<Content: View>(
        _ title: String,
        height: CGFloat,
        width: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .background(.black, in: RoundedRectangle(cornerRadius: 22))
                .environment(\.colorScheme, .dark)
        }
    }
}
