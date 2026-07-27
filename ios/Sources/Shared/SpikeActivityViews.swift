import SwiftUI

/// The Live Activity presentations, shared between the widget extension that ships them
/// and the in-app harness that previews them.
///
/// They live here rather than in the widget target because there are no SwiftUI previews
/// available on a headless build machine — the only way to iterate on a layout is to look
/// at it on the phone, which means the app has to be able to render it too.

struct SpikeLockScreenView: View {
    let state: SpikeAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tick \(state.tick)")
                    .font(.headline)
                    .monospacedDigit()
                Text(state.mechanism)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(state.fixDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(state.maxGap.shortDuration)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(state.isHealthy ? .green : .red)
                Text("max gap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(state.elapsed.shortDuration + " elapsed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct SpikeExpandedLeadingView: View {
    let state: SpikeAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tick").font(.caption2).foregroundStyle(.secondary)
            Text("\(state.tick)").font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}

struct SpikeExpandedTrailingView: View {
    let state: SpikeAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Max gap").font(.caption2).foregroundStyle(.secondary)
            Text(state.maxGap.shortDuration)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(state.isHealthy ? .green : .red)
        }
    }
}

struct SpikeExpandedBottomView: View {
    let state: SpikeAttributes.ContentState

    var body: some View {
        HStack {
            Text(state.mechanism)
            Spacer()
            Text(state.fixDescription)
            Spacer()
            Text(state.elapsed.shortDuration)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct SpikeCompactTrailingView: View {
    let state: SpikeAttributes.ContentState

    var body: some View {
        Text("\(Int(state.maxGap))s")
            .monospacedDigit()
            .foregroundStyle(state.isHealthy ? .green : .red)
    }
}

struct SpikeMinimalView: View {
    let state: SpikeAttributes.ContentState

    var body: some View {
        Image(systemName: state.isHealthy ? "dot.radiowaves.left.and.right" : "exclamationmark.triangle.fill")
            .foregroundStyle(state.isHealthy ? .green : .red)
    }
}
