import SwiftUI

struct JourneyOptionsView: View {
    @EnvironmentObject private var model: AppModel

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = TimeZone(identifier: "Australia/Sydney")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(model.journeys) { journey in
                    card(journey)
                        .onTapGesture {
                            withAnimation(.snappy) { model.selectedJourneyID = journey.id }
                        }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: model.selectedJourneyID)
    }

    private func card(_ journey: Journey) -> some View {
        let selected = journey.id == model.selectedJourneyID
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(journey.transitLegs.prefix(4)) { leg in
                    Text(leg.route ?? leg.mode.displayName)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(leg.mode.tint))
                        .foregroundStyle(.white)
                }
            }
            if let departure = journey.departure, let arrival = journey.arrival {
                Text("\(Self.clock.string(from: departure)) → \(Self.clock.string(from: arrival))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            if let duration = journey.duration {
                Text("\(Int(duration / 60)) min")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.m)
        .frame(width: 190, alignment: .leading)
        .glassSurface(cornerRadius: Theme.Radius.pill)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                .strokeBorder(selected ? Theme.Colors.textPrimary : .clear, lineWidth: 2)
        )
        .scaleEffect(selected ? 1 : 0.95)
        .animation(.snappy, value: selected)
    }
}
