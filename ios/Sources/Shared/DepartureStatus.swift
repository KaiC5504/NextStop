import SwiftUI

/// Lives in Shared because the Live Activity renders status on the Lock Screen. The
/// `Leg`-aware initialiser stays in the app target — `Leg` never ships to the widget.
enum DepartureStatus: Hashable, Codable {
    case onTime
    case late(Int)
    case early(Int)
    case scheduledOnly

    var label: String {
        switch self {
        case .onTime: "On time"
        case .late(let minutes): "\(minutes) min late"
        case .early(let minutes): "\(minutes) min early"
        case .scheduledOnly: "Scheduled only"
        }
    }

    var tint: Color {
        switch self {
        case .onTime: Theme.Colors.onTime
        case .late(let minutes): minutes >= 5 ? Theme.Colors.veryLate : Theme.Colors.late
        case .early: Theme.Colors.late
        case .scheduledOnly: Theme.Colors.noRealtime
        }
    }
}
