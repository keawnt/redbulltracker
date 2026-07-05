import SwiftUI

/// Boarding-pass style weekly recap card, in the Flighty "flight passport" spirit.
///
/// IMPORTANT: This view is rendered to a shareable PNG through `ImageRenderer`,
/// so it deliberately uses NO `.glassEffect()` anywhere — Liquid Glass does not
/// rasterize reliably. Every surface is an opaque dark layer with explicit
/// colors so the exported image looks exactly like the on-screen preview.
struct RecapCard: View {
    let weekOf: Date
    let logs: [CanLog]

    init(weekOf: Date, logs: [CanLog]) {
        self.weekOf = weekOf
        self.logs = logs
    }

    // MARK: - Derived stats

    private var weekLogs: [CanLog] { StatsEngine.logs(logs, inWeekOf: weekOf) }

    private var weekCount: Int { StatsEngine.weekCount(logs, weekOf: weekOf) }

    private var dayStats: [DayStat] { StatsEngine.dailyStats(logs, weekOf: weekOf) }

    private var weekNumber: Int {
        // User-calendar week number, sampled mid-week — keeps the recap label
        // in agreement with StatsView.isoWeekNumber and dodges the Sunday /
        // ISO-Monday boundary (confirmed review finding).
        let midWeek = Calendar.current.date(byAdding: .day, value: 3, to: weekOf) ?? weekOf
        return Calendar.current.component(.weekOfYear, from: midWeek)
    }

    private var topFlavor: String {
        StatsEngine.flavorBreakdown(weekLogs).first?.flavor ?? "—"
    }

    private var caffeineTotal: Int {
        dayStats.reduce(0) { $0 + $1.caffeineMG }
    }

    private var biggestDay: String {
        guard let best = dayStats.max(by: { $0.count < $1.count }), best.count > 0 else {
            return "—"
        }
        return "\(best.day.formatted(.dateTime.weekday(.wide))) · \(best.count)"
    }

    /// Consecutive-day run ending at the last logged day of this week,
    /// walking backwards through the full log history.
    private var streak: Int {
        let calendar = Calendar.current
        let daysWithLogs = Set(logs.map { calendar.startOfDay(for: $0.timestamp) })
        guard let lastDayInWeek = weekLogs
            .map({ calendar.startOfDay(for: $0.timestamp) })
            .max()
        else { return 0 }

        var run = 0
        var cursor = lastDayInWeek
        while daysWithLogs.contains(cursor) {
            run += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return run
    }

    private var dateRange: String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: weekOf) ?? weekOf
        let style: Date.FormatStyle = .dateTime.month(.abbreviated).day()
        return "\(weekOf.formatted(style)) – \(end.formatted(style))".uppercased()
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)

            hero
                .padding(.horizontal, 24)
                .padding(.bottom, 22)

            perforation

            statGrid
                .padding(.horizontal, 24)
                .padding(.vertical, 22)

            barcode
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background {
            // Opaque dark layers only — see note at the top of the file.
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#191920"), Color(hex: "#0C0C10")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Week \(weekNumber) recap. \(weekCount) cans. Top flavor \(topFlavor). \(caffeineTotal) milligrams of caffeine."
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CANCOUNT")
                    .font(Theme.label(13))
                    .kerning(3.5)
                    .foregroundStyle(Theme.energyYellow)
                MicroLabel(text: "Week \(weekNumber) recap")
            }
            Spacer()
            Image(systemName: "bolt.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.energyYellow)
                .accessibilityHidden(true)
        }
    }

    private var hero: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
            Text("\(weekCount)")
                .font(Theme.heroFont(88))
                .foregroundStyle(.white)
                .accessibilityLabel("\(weekCount) cans this week")

            VStack(alignment: .leading, spacing: 5) {
                MicroLabel(text: "Cans")
                Text(dateRange)
                    .font(Theme.label(10))
                    .kerning(1.5)
                    .foregroundStyle(.white.opacity(0.35))
            }
            Spacer()
        }
    }

    /// Punch-hole perforation divider, boarding-pass style. The canvas-colored
    /// circles overhang the edges and get trimmed by the card's clip shape.
    private var perforation: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.canvas)
                .frame(width: 18, height: 18)
                .offset(x: -9)

            RecapPerforationLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .foregroundStyle(.white.opacity(0.15))
                .frame(height: 1)

            Circle()
                .fill(Theme.canvas)
                .frame(width: 18, height: 18)
                .offset(x: 9)
        }
        .accessibilityHidden(true)
    }

    private var statGrid: some View {
        // Non-lazy Grid on purpose: lazy containers are unreliable in ImageRenderer.
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 20) {
            GridRow {
                statCell(label: "Top flavor", value: topFlavor)
                statCell(label: "Biggest day", value: biggestDay)
            }
            GridRow {
                statCell(label: "Caffeine", value: "\(caffeineTotal.formatted()) mg")
                statCell(
                    label: "Streak",
                    value: streak == 0 ? "—" : "\(streak) day\(streak == 1 ? "" : "s")"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MicroLabel(text: label)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Decorative fake barcode. Widths are derived from the ISO week number so
    /// each week's recap gets its own stable stripe pattern.
    private var barcode: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<36, id: \.self) { index in
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: barWidth(index), height: 34)
                }
                Spacer(minLength: 0)
            }
            Text(String(format: "CC-%02d-RB-%04d", weekNumber, weekCount * 137 + weekNumber))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .accessibilityHidden(true)
    }

    private func barWidth(_ index: Int) -> CGFloat {
        let widths: [CGFloat] = [1.5, 3, 2, 4.5]
        return widths[(weekNumber * 7 + index * 13) % widths.count]
    }

    private var footer: some View {
        HStack {
            Text("CANCOUNT")
                .font(Theme.label(10))
                .kerning(3)
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
            Text(weekCount == 0 ? "Zero cans. Suspicious." : "Logged. Hydrate accordingly.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

/// Simple horizontal line shape for the dashed perforation stroke.
private struct RecapPerforationLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
