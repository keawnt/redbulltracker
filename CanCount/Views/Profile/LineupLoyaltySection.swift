import SwiftUI

/// Which Red Bull family owns you — Original, Sugarfree, Zero, or the
/// Editions rainbow. Animated share bars over the lifetime logs.
struct LineupLoyaltySection: View {
    let logs: [CanLog]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barsGrown = false

    init(logs: [CanLog]) {
        self.logs = logs
    }

    private var slices: [FlavorSlice] { StatsEngine.lineupBreakdown(logs) }
    private var total: Int { slices.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Lineup loyalty")

            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    if total == 0 {
                        Text("No lineup data. Drink something.")
                            .font(Theme.label(12))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(loyaltyLine)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 12) {
                            ForEach(slices) { slice in
                                lineupRow(slice)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if reduceMotion {
                barsGrown = true
            } else {
                withAnimation(Theme.spring.delay(0.15)) { barsGrown = true }
            }
        }
    }

    private var loyaltyLine: String {
        guard let top = slices.first, total > 0 else { return "" }
        let share = Double(top.count) / Double(total)
        guard share >= 0.5 else {
            return "No allegiance. The whole lineup gets a turn."
        }
        switch top.flavor {
        case "Editions": return "Editions loyalist. The rainbow is the point."
        case "Sugarfree": return "Sugarfree operative. Discipline in a can."
        case "Zero": return "Zero hour, every hour."
        default: return "Original purist. Respect the classic."
        }
    }

    private func lineupRow(_ slice: FlavorSlice) -> some View {
        let fraction = total > 0 ? Double(slice.count) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(slice.flavor.uppercased())
                    .font(Theme.label(10))
                    .kerning(1.6)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(slice.count)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.07))
                    Capsule()
                        .fill(slice.accent)
                        .frame(width: max(6, geo.size.width * fraction * (barsGrown ? 1 : 0)))
                        .shadow(color: slice.accent.opacity(0.5), radius: 4)
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slice.flavor): \(slice.count) cans, \(Int((fraction * 100).rounded())) percent")
    }
}
