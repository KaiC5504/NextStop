import SwiftUI

/// The vertical route list in the Home sheet: one row per alternative, Google style —
/// times with the big duration, the leg sequence, then the realtime status line.
struct JourneyOptionsList: View {
    @EnvironmentObject private var model: AppModel
    let detent: SheetDetent
    /// Called after a tap has set the selection; the caller owns navigation.
    var onOpen: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text("Routes")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    PlanTimeControl()
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.s)

                ForEach(model.journeys) { journey in
                    row(journey)
                    if journey.id != model.journeys.last?.id {
                        Divider().overlay(Theme.Colors.stroke)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
        }
        .scrollIndicators(.hidden)
        // At medium a vertical swipe drags the sheet; only the large detent scrolls the
        // list, so the two gestures never fight.
        .scrollDisabled(detent != .large)
        .frame(maxHeight: 480)
        .sensoryFeedback(.selection, trigger: model.selectedJourneyID)
    }

    private func row(_ journey: Journey) -> some View {
        let selected = journey.id == model.selectedJourneyID
        return Button {
            withAnimation(.snappy) { model.selectedJourneyID = journey.id }
            onOpen()
        } label: {
            JourneyOptionRow(journey: journey)
            .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xs)
            .padding(.horizontal, Theme.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(selected ? Theme.Colors.surface : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .strokeBorder(selected ? Theme.Colors.textPrimary : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: selected)
    }
}
