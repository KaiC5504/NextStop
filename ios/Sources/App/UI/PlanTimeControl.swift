import SwiftUI

/// "Leave now / Depart at / Arrive by" — the trip-time control above the route list.
struct PlanTimeControl: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingPicker = false
    @State private var choice: Choice = .leaveNow
    @State private var date = Date()

    private enum Choice: String, CaseIterable, Identifiable {
        case leaveNow = "Leave now"
        case departAt = "Depart at"
        case arriveBy = "Arrive by"
        var id: String { rawValue }
    }

    var body: some View {
        Button {
            syncFromModel()
            showingPicker = true
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "clock")
                    .font(.caption)
                Text(model.planTimeSelection.label)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.s + Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.s)
            .background(Capsule().fill(Theme.Colors.surface))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPicker) { picker }
    }

    private var picker: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                Picker("When", selection: $choice) {
                    ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if choice != .leaveNow {
                    DatePicker(
                        "Time", selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.m)
            .navigationTitle("Trip time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showingPicker = false
                        Task { await model.setPlanTime(selection) }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingPicker = false }
                }
            }
        }
        .presentationDetents(choice == .leaveNow ? [.medium] : [.large])
        .preferredColorScheme(.dark)
    }

    private var selection: PlanTimeSelection {
        switch choice {
        case .leaveNow: .leaveNow
        case .departAt: .departAt(date)
        case .arriveBy: .arriveBy(date)
        }
    }

    /// The sheet edits a copy; reopening it must show what is actually in force.
    private func syncFromModel() {
        switch model.planTimeSelection {
        case .leaveNow:
            choice = .leaveNow
            date = Date()
        case .departAt(let current):
            choice = .departAt
            date = current
        case .arriveBy(let current):
            choice = .arriveBy
            date = current
        }
    }
}
