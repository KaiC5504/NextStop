import SwiftUI

enum Theme {
    enum Colors {
        static let background = Color(red: 0.04, green: 0.05, blue: 0.07)
        static let surface = Color.white.opacity(0.08)
        static let stroke = Color.white.opacity(0.12)
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.6)

        static let onTime = Color(hex: 0x55A868)
        static let late = Color(hex: 0xDD8452)
        static let veryLate = Color(hex: 0xC44E52)
        // Deliberately grey rather than a warning colour. Absent realtime is not a problem
        // with the service, it is a limit on what the app can honestly claim.
        static let noRealtime = Color.white.opacity(0.45)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 40
    }

    enum Radius {
        static let card: CGFloat = 28
        static let pill: CGFloat = 12
    }
}

extension Color {
    /// Mode colours are published as hex by TfNSW. Storing them as hex rather than decimal
    /// components keeps them checkable against the brand guidance by eye.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
