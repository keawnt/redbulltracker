import SwiftUI

/// A compact glass stat pill: big rounded numeral on top, tracked-out
/// micro-label beneath. Designed to sit in an `HStack` row of three — each
/// pill greedily takes an equal share of the width.
struct StatPill: View {
    private let title: String
    private let value: String
    private let accent: Color
    private let systemImage: String?

    init(
        title: String,
        value: String,
        accent: Color = Theme.energyYellow,
        systemImage: String? = nil
    ) {
        self.title = title
        self.value = value
        self.accent = accent
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accent)
                }
                Text(value)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            MicroLabel(text: title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(accent.opacity(0.16)), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

#Preview("StatPill row") {
    ZStack {
        Theme.canvas.ignoresSafeArea()
        HStack(spacing: 12) {
            StatPill(title: "Today", value: "3", systemImage: "checkmark.seal.fill")
            StatPill(title: "Caffeine", value: "240mg", accent: Theme.bullRed, systemImage: "bolt.fill")
            StatPill(title: "Streak", value: "12", accent: Theme.racingBlue, systemImage: "flame.fill")
        }
        .padding(20)
    }
    .preferredColorScheme(.dark)
}
