import SwiftUI

/// Renders every Live Activity presentation at roughly its real size against mock state.
///
/// Xcode previews are unavailable when the build machine is remote, so this is how the
/// layouts get iterated: change the shared views, ship a build, look at the phone — or at
/// the CI screenshot, which launches straight here with `-initialScreen layouts`. The
/// journey scenarios cover each phase plus the failure stylings (very late, scheduled
/// only, stale) without having to ride anything.
struct ActivityHarnessView: View {
    private enum Family: String, CaseIterable {
        case journey = "Journey"
        case spike = "Spike"
    }

    private enum JourneyScenario: String, CaseIterable, Identifiable {
        case waitingLate = "Waiting · very late bus"
        case waitingOnTime = "Waiting · on time"
        case riding = "Riding the Metro"
        case ridingNoStops = "Riding · no stop data"
        case walking = "Walking · connection"
        case scheduledOnly = "Scheduled only"
        case arrived = "Arrived"

        var id: String { rawValue }
    }

    @State private var family: Family = .journey
    // Riding first: it is the layout with the most going on (station ticks, stop
    // counter, next-stop caption), and the CI screenshot captures only the default.
    @State private var scenario: JourneyScenario = .riding
    @State private var isStale = false

    @State private var tick = 128
    @State private var maxGap: TimeInterval = 4.2
    @State private var hasFix = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Family", selection: $family) {
                        ForEach(Family.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    switch family {
                    case .journey: journeySections
                    case .spike: spikeSections
                    }
                }
                .padding()
            }
            .navigationTitle("Layouts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Journey

    /// Offsets are relative to `Date()` so the timers visibly tick in the harness,
    /// exactly as they will on the Lock Screen.
    private var journeyState: JourneyActivityAttributes.ContentState {
        let now = Date()
        return switch scenario {
        case .waitingLate:
            .init(
                phase: .waiting, mode: .bus, routeBadge: "333", headsign: "Bondi Beach",
                place: "Railway Square", countdownStart: now.addingTimeInterval(-540),
                countdownEnd: now.addingTimeInterval(260), status: .late(6),
                arrivalShort: "5:58 pm", legIndex: 2, legCount: 3, nextLegLine: nil
            )
        case .waitingOnTime:
            .init(
                phase: .waiting, mode: .train, routeBadge: "T1", headsign: "Central via Gordon",
                place: "Chatswood", countdownStart: now.addingTimeInterval(-300),
                countdownEnd: now.addingTimeInterval(230), status: .onTime,
                arrivalShort: "5:42 pm", legIndex: 2, legCount: 4, nextLegLine: nil
            )
        case .riding:
            .init(
                phase: .riding, mode: .metro, routeBadge: "M1", headsign: "Tallawong",
                place: "Martin Place", countdownStart: now.addingTimeInterval(-380),
                countdownEnd: now.addingTimeInterval(520), status: .onTime,
                arrivalShort: "8:14 am", legIndex: 1, legCount: 1, nextLegLine: nil,
                stopIndex: 3, stopCount: 11, nextStopName: "St Leonards",
                // Deliberately uneven, like a real stopping pattern.
                stopFractions: [0.06, 0.13, 0.22, 0.28, 0.41, 0.55, 0.63, 0.78, 0.9]
            )
        case .ridingNoStops:
            .init(
                phase: .riding, mode: .bus, routeBadge: "428", headsign: "Canterbury",
                place: "Newtown", countdownStart: now.addingTimeInterval(-300),
                countdownEnd: now.addingTimeInterval(700), status: .onTime,
                arrivalShort: "11:06 pm", legIndex: 2, legCount: 2, nextLegLine: nil
            )
        case .walking:
            .init(
                phase: .walking, mode: .walk, routeBadge: nil, headsign: nil,
                place: "Chatswood Station", countdownStart: now.addingTimeInterval(-60),
                countdownEnd: now.addingTimeInterval(240), status: .late(3),
                arrivalShort: "8:51 am", legIndex: 1, legCount: 3,
                nextLegLine: "Then T1 · 8:12 am"
            )
        case .scheduledOnly:
            .init(
                phase: .waiting, mode: .lightRail, routeBadge: "L2", headsign: "Circular Quay",
                place: "Central Chalmers St", countdownStart: now.addingTimeInterval(-120),
                countdownEnd: now.addingTimeInterval(420), status: .scheduledOnly,
                arrivalShort: "6:20 pm", legIndex: 1, legCount: 2, nextLegLine: nil
            )
        case .arrived:
            .init(
                phase: .arrived, mode: .train, routeBadge: nil, headsign: nil,
                place: "University of Sydney", countdownStart: now.addingTimeInterval(-2_400),
                countdownEnd: now.addingTimeInterval(-300), status: .onTime,
                arrivalShort: "9:02 am", legIndex: 3, legCount: 3, nextLegLine: nil
            )
        }
    }

    @ViewBuilder
    private var journeySections: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Scenario", selection: $scenario) {
                ForEach(JourneyScenario.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("Stale — updates stopped", isOn: $isStale)
        }
        .padding()
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

        // Tall enough for the riding scenario's extra stop caption; a shorter frame
        // clips it and the screenshot lies.
        presentation("Lock Screen", height: 124) {
            JourneyLockScreenView(state: journeyState, isStale: isStale)
        }

        presentation("Dynamic Island — expanded", height: 150) {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    JourneyExpandedLeadingView(state: journeyState)
                    Spacer()
                    JourneyExpandedTrailingView(state: journeyState, isStale: isStale)
                }
                JourneyExpandedBottomView(state: journeyState, isStale: isStale)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }

        HStack(spacing: 16) {
            presentation("Compact", height: 40, width: 180) {
                HStack(spacing: 6) {
                    JourneyCompactLeadingView(state: journeyState).font(.caption)
                    Spacer(minLength: 0)
                    JourneyCompactTrailingView(state: journeyState, isStale: isStale).font(.caption)
                }
                .padding(.horizontal, 14)
            }

            presentation("Minimal", height: 40, width: 60) {
                JourneyMinimalView(state: journeyState).font(.caption)
            }
        }
    }

    // MARK: Spike

    private var spikeState: SpikeAttributes.ContentState {
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

    @ViewBuilder
    private var spikeSections: some View {
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

        presentation("Lock Screen", height: 92) {
            SpikeLockScreenView(state: spikeState)
        }

        presentation("Dynamic Island — expanded", height: 116) {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    SpikeExpandedLeadingView(state: spikeState)
                    Spacer()
                    SpikeExpandedTrailingView(state: spikeState)
                }
                SpikeExpandedBottomView(state: spikeState)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }

        HStack(spacing: 16) {
            presentation("Compact", height: 40, width: 180) {
                HStack(spacing: 6) {
                    Image(systemName: "tram.fill").font(.caption)
                    Spacer(minLength: 0)
                    SpikeCompactTrailingView(state: spikeState).font(.caption)
                }
                .padding(.horizontal, 14)
            }

            presentation("Minimal", height: 40, width: 60) {
                SpikeMinimalView(state: spikeState).font(.caption)
            }
        }
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
