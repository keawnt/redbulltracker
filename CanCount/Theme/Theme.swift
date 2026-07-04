import SwiftUI

enum Theme {
    // Palette
    static let canvas = Color(hex: "#0A0A0C")
    static let energyYellow = Color(hex: "#FFC906")
    static let racingBlueDark = Color(hex: "#001E50")
    static let racingBlue = Color(hex: "#2E5FDF")
    static let bullRed = Color(hex: "#DB0A40")
    static let silver = Color(hex: "#C8CDD4")

    static let cardRadius: CGFloat = 28

    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Massive hero numeral font.
    static func heroFont(_ size: CGFloat = 120) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

extension Color {
    nonisolated init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// Tracked-out uppercase micro-label, 50% white — the app's signature label style.
struct MicroLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(11))
            .kerning(2)
            .foregroundStyle(.white.opacity(0.5))
    }
}

enum Copy {
    static let greetings: [Int: String] = [
        1: "Sunday. Rest is optional.",
        2: "Monday. You know what to do.",
        3: "Tuesday. The cans won't drink themselves.",
        4: "Wednesday. Halfway there.",
        5: "Thursday. You know what to do.",
        6: "Friday. Send it.",
        7: "Saturday. No judgment here.",
    ]

    static func greeting(for date: Date = .now) -> String {
        greetings[Calendar.current.component(.weekday, from: date)] ?? "You know what to do."
    }

    static func todayLine(count: Int) -> String {
        switch count {
        case 0: "Zero cans. Suspicious."
        case 1: "1 today. Warming up."
        case 2: "2 today. Cruising altitude."
        case 3: "3 today. Your heart rate agrees."
        default: "\(count) today. Please drink water."
        }
    }

    static let notARedBull = "That's not a Red Bull. We both know it."
    static let newPR = "New PR. Please drink water."
    static let emptyRecents = "No sips yet. The fridge is right there."
    static let emptyStats = "No data. Charts need cans."
    static let emptyLeaderboard = "No crew yet. Greatness needs witnesses."
}
