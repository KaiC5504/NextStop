import SwiftUI

/// TfNSW product classes, per the Trip Planner v3.3 manual and confirmed against live
/// responses. Colours are the published TfNSW mode colours — using anything else costs the
/// instant recognition that makes a transit map readable at a glance.
///
/// String raw values exist so the Live Activity payload can encode a mode. The case names
/// are separately load-bearing: `Leg.id` interpolates them, so renaming one orphans every
/// saved leg rating. Both contracts are pinned by tests.
enum TransitMode: String, Codable, Equatable {
    case train, metro, lightRail, bus, coach, ferry, schoolBus, walk, cycle, unknown

    init(productClass: Int?) {
        switch productClass {
        case 1: self = .train
        case 2: self = .metro
        case 4: self = .lightRail
        case 5: self = .bus
        case 7: self = .coach
        case 9: self = .ferry
        case 11: self = .schoolBus
        // TfNSW uses both 99 and 100 for walking in the same response.
        case 99, 100: self = .walk
        case 107: self = .cycle
        default: self = .unknown
        }
    }

    var isWalking: Bool { self == .walk || self == .cycle }

    var displayName: String {
        switch self {
        case .train: "Train"
        case .metro: "Metro"
        case .lightRail: "Light Rail"
        case .bus: "Bus"
        case .coach: "Coach"
        case .ferry: "Ferry"
        case .schoolBus: "School Bus"
        case .walk: "Walk"
        case .cycle: "Cycle"
        case .unknown: "Service"
        }
    }

    var symbolName: String {
        switch self {
        case .train: "tram.fill"
        case .metro: "train.side.front.car"
        case .lightRail: "cablecar.fill"
        case .bus: "bus.fill"
        case .coach: "bus.doubledecker.fill"
        case .ferry: "ferry.fill"
        case .schoolBus: "bus"
        case .walk: "figure.walk"
        case .cycle: "bicycle"
        case .unknown: "questionmark.circle"
        }
    }

    /// Stated by TfNSW staff on the Open Data forum, thread 1040. Light Rail is the mode
    /// colour, not the L2 line colour (#DD1E25) — individual lines are branded separately
    /// and this app colours by mode.
    var tint: Color {
        switch self {
        case .train: Color(hex: 0xF6891F)
        case .metro: Color(hex: 0x168388)
        case .lightRail: Color(hex: 0xEE343F)
        case .bus, .schoolBus: Color(hex: 0x00B5EF)
        case .coach: Color(hex: 0x732A82)
        case .ferry: Color(hex: 0x5AB031)
        case .walk, .cycle: Theme.Colors.noRealtime
        case .unknown: Theme.Colors.textSecondary
        }
    }
}
