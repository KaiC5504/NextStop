import Foundation

/// A concrete trip-time request: EFA's `depArrMacro` plus the date it applies to.
enum PlanTime: Equatable {
    case depart(Date)
    case arrive(Date)

    var macro: String {
        switch self {
        case .depart: "dep"
        case .arrive: "arr"
        }
    }

    var date: Date {
        switch self {
        case .depart(let date), .arrive(let date): date
        }
    }
}

/// What the user picked in the trip-time control. Resolution to a `PlanTime` happens
/// once per plan, so "leave now" pins to the moment of planning and the 30-second
/// refresh keeps re-asking the same question instead of sliding forward.
enum PlanTimeSelection: Equatable {
    case leaveNow
    case departAt(Date)
    case arriveBy(Date)

    func resolved(now: Date) -> PlanTime {
        switch self {
        case .leaveNow: .depart(now)
        case .departAt(let date): .depart(date)
        case .arriveBy(let date): .arrive(date)
        }
    }

    var label: String {
        switch self {
        case .leaveNow: "Leave now"
        case .departAt(let date): "Depart \(TimeDisplay.clock.string(from: date))"
        case .arriveBy(let date): "Arrive by \(TimeDisplay.clock.string(from: date))"
        }
    }
}
