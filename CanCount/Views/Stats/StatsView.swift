import SwiftUI
import SwiftData
import Charts

/// The Stats tab: weekly bar chart with caffeine overlay, lifetime flavor
/// donut, flavor personality, lifetime totals with rotating absurd caffeine
/// equivalents, and the shareable weekly recap card.
struct StatsView: View {
    @Query(sort: \CanLog.timestamp, order: .reverse) private var logs: [CanLog]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedWeek: Date = StatsEngine.startOfWeek(containing: .now)
    /// Drives bar/line growth: chart y-values are multiplied by this, animated 0 → 1.
    @State private var barProgress: Double = 0
    @State private var showCaffeine = false
    @State private var equivalentIndex = 0
    @State private var recapImage: Image?

    init() {}

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    weekSelector

                    if logs.isEmpty {
                        emptyState
                    } else {
                        chartCard
                        donutCard
                        personalityCard
                        lifetimeSection
                        recapSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 130)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedWeek)
        .sensoryFeedback(.impact(weight: .light), trigger: showCaffeine)
        // Week rollover: if the user was looking at "this week" when the
        // week flipped (midnight Sunday, or returning days later), follow
        // them into the new week — otherwise a historical selection stays put.
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSCalendarDayChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            reanchorWeekIfStale()
        }
        .onAppear { reanchorWeekIfStale() }
        .task(id: selectedWeek) {
            // Re-run the bar growth animation whenever the week changes
            // (and on first appear). The short sleep lets SwiftUI commit the
            // zeroed state before we animate up, so the growth is visible.
            barProgress = 0
            try? await Task.sleep(for: .milliseconds(60))
            if reduceMotion {
                barProgress = 1
            } else {
                withAnimation(Theme.spring) { barProgress = 1 }
            }
        }
        .task(id: recapRenderKey) {
            recapImage = renderRecapImage()
        }
        .task {
            // Rotate the absurd caffeine equivalents line every few seconds.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    break
                }
                if reduceMotion {
                    equivalentIndex += 1
                } else {
                    withAnimation(Theme.spring) { equivalentIndex += 1 }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(text: "The damage")
            Text("Stats")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Week selector

    private var weeks: [Date] {
        let calendar = Calendar.current
        let thisWeek = StatsEngine.startOfWeek(containing: .now)
        return (0..<8).compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
    }

    private func weekLabel(_ week: Date, index: Int) -> String {
        switch index {
        case 0: "This week"
        case 1: "Last week"
        default: week.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private var weekSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer {
                HStack(spacing: 10) {
                    ForEach(Array(weeks.enumerated()), id: \.element) { index, week in
                        weekChip(week, index: index)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }

    private func weekChip(_ week: Date, index: Int) -> some View {
        let isSelected = week == selectedWeek
        return Button {
            if reduceMotion {
                selectedWeek = week
            } else {
                withAnimation(Theme.spring) { selectedWeek = week }
            }
        } label: {
            Text(weekLabel(week, index: index).uppercased())
                .font(Theme.label(12))
                .kerning(1.2)
                .foregroundStyle(isSelected ? Theme.energyYellow : .white.opacity(0.55))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(
                    isSelected
                        ? .regular.tint(Theme.energyYellow.opacity(0.28)).interactive()
                        : .regular.interactive(),
                    in: .capsule
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week of \(week.formatted(.dateTime.month(.wide).day()))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Weekly bar chart

    private var chartCard: some View {
        let dayStats = StatsEngine.dailyStats(logs, weekOf: selectedWeek)
        let weekTotal = StatsEngine.weekCount(logs, weekOf: selectedWeek)
        let isPR = StatsEngine.isPersonalRecordWeek(logs, weekOf: selectedWeek)

        return GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        MicroLabel(text: "Cans per day")
                        HStack(spacing: 10) {
                            Text("\(weekTotal)")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .accessibilityLabel("\(weekTotal) cans this week")
                            if isPR && weekTotal > 0 {
                                prPill
                            }
                        }
                    }
                    Spacer()
                    caffeineToggle
                }

                weekChart(dayStats)

                if weekTotal == 0 {
                    Text("Zero-can week. Historic.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    private var prPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 10, weight: .bold))
            Text("PR WEEK")
                .font(Theme.label(10))
                .kerning(1.5)
        }
        .foregroundStyle(Theme.canvas)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.energyYellow))
        .accessibilityLabel("Personal record week")
    }

    private var caffeineToggle: some View {
        Button {
            if reduceMotion {
                showCaffeine.toggle()
            } else {
                withAnimation(Theme.spring) { showCaffeine.toggle() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("MG")
                    .font(Theme.label(11))
                    .kerning(1.5)
            }
            .foregroundStyle(showCaffeine ? Theme.racingBlue : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassEffect(
                showCaffeine
                    ? .regular.tint(Theme.racingBlue.opacity(0.35)).interactive()
                    : .regular.interactive(),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showCaffeine ? "Hide caffeine overlay" : "Show caffeine overlay")
    }

    private func weekChart(_ dayStats: [DayStat]) -> some View {
        let caffeineFactor = caffeineScale(dayStats)

        return Chart {
            ForEach(dayStats) { stat in
                BarMark(
                    x: .value("Day", stat.day, unit: .day),
                    y: .value("Cans", Double(stat.count) * barProgress)
                )
                .cornerRadius(6)
                .foregroundStyle(barStyle(for: stat))
            }

            if showCaffeine {
                ForEach(dayStats) { stat in
                    LineMark(
                        x: .value("Day", stat.day, unit: .day),
                        y: .value("Caffeine", Double(stat.caffeineMG) * caffeineFactor * barProgress)
                    )
                    .foregroundStyle(Theme.racingBlue)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", stat.day, unit: .day),
                        y: .value("Caffeine", Double(stat.caffeineMG) * caffeineFactor * barProgress)
                    )
                    .foregroundStyle(Theme.racingBlue)
                    .symbolSize(50)
                    .annotation(position: .top, spacing: 4) {
                        if stat.caffeineMG > 0 {
                            Text("\(stat.caffeineMG)")
                                .font(Theme.label(8))
                                .foregroundStyle(Theme.racingBlue)
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: dayStats.map(\.day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    .foregroundStyle(.white.opacity(0.45))
                    .font(Theme.label(11))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.35))
                    .font(Theme.label(10))
            }
        }
        .chartYScale(domain: 0...yDomainMax(dayStats))
        .frame(height: 200)
        .accessibilityLabel("Bar chart of cans per day for the selected week")
    }

    /// Today's bar glows yellow; every other day wears its dominant flavor accent.
    private func barStyle(for stat: DayStat) -> AnyShapeStyle {
        if Calendar.current.isDateInToday(stat.day) {
            return AnyShapeStyle(
                Theme.energyYellow
                    .shadow(.drop(color: Theme.energyYellow.opacity(0.7), radius: 8))
            )
        }
        return AnyShapeStyle(stat.dominantAccent)
    }

    /// Maps caffeine mg into the can-count y-domain so the overlay shares the axis.
    private func caffeineScale(_ dayStats: [DayStat]) -> Double {
        let maxCaffeine = dayStats.map(\.caffeineMG).max() ?? 0
        guard maxCaffeine > 0 else { return 0 }
        let maxCount = max(dayStats.map(\.count).max() ?? 0, 1)
        return Double(maxCount) / Double(maxCaffeine)
    }

    private func yDomainMax(_ dayStats: [DayStat]) -> Int {
        max((dayStats.map(\.count).max() ?? 0) + 1, 4)
    }

    // MARK: - Flavor donut

    private var donutCard: some View {
        let slices = StatsEngine.flavorBreakdown(logs)
        let total = slices.reduce(0) { $0 + $1.count }

        return GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                MicroLabel(text: "Flavor split")

                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Cans", slice.count),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(by: .value("Flavor", slice.flavor))
                }
                .chartForegroundStyleScale(
                    domain: slices.map(\.flavor),
                    range: slices.map(\.accent)
                )
                .chartLegend(position: .bottom, alignment: .center, spacing: 14)
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let anchor = proxy.plotFrame {
                            let frame = geometry[anchor]
                            VStack(spacing: 2) {
                                Text("\(total)")
                                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                    .contentTransition(.numericText())
                                    .accessibilityLabel("\(total) total cans")
                                MicroLabel(text: "Cans")
                            }
                            .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
                .frame(height: 250)
            }
        }
    }

    // MARK: - Personality

    private var personalityCard: some View {
        let slices = StatsEngine.flavorBreakdown(logs)
        let personality = StatsEngine.personality(slices)

        return GlassCard(tint: slices.first?.accent) {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(text: "Flavor personality")
                Text(personality.title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.energyYellow)
                Text(personality.line)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Lifetime

    private var lifetimeSection: some View {
        let lifetime = StatsEngine.lifetime(logs)

        return VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Lifetime damage")
            HStack(spacing: 10) {
                StatPill(
                    title: "Cans",
                    value: "\(lifetime.cans)",
                    accent: Theme.energyYellow,
                    systemImage: "flame.fill"
                )
                StatPill(
                    title: "Liters",
                    value: String(format: "%.1f", lifetime.liters),
                    accent: Theme.racingBlue,
                    systemImage: "drop.fill"
                )
                StatPill(
                    title: "Caffeine",
                    value: "\(lifetime.caffeineMG.formatted())mg",
                    accent: Theme.bullRed,
                    systemImage: "bolt.fill"
                )
            }
            equivalentsLine(lifetime)
        }
    }

    private func equivalentsLine(_ lifetime: LifetimeStats) -> some View {
        let lines = equivalentLines(lifetime)
        let line = lines[equivalentIndex % lines.count]

        return Text(line)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
            .id(line)
            .transition(reduceMotion ? .opacity : .push(from: .bottom))
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Caffeine equivalent: \(line)")
    }

    private func equivalentLines(_ lifetime: LifetimeStats) -> [String] {
        var lines = [
            "= \(lifetime.espressos) espressos",
            "= \(lifetime.caffeineMG / 95) cups of drip coffee",
        ]
        if lifetime.caffeineMG >= 4000 {
            lines.append("= enough to wake a small horse")
        }
        return lines
    }

    // MARK: - Weekly recap

    private var recapSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Weekly recap")

            RecapCard(weekOf: selectedWeek, logs: logs)

            if let recapImage {
                ShareLink(
                    item: recapImage,
                    preview: SharePreview(
                        "CanCount — Week \(isoWeekNumber(of: selectedWeek)) Recap",
                        image: recapImage
                    )
                ) {
                    Label("Share recap", systemImage: "square.and.arrow.up")
                        .font(Theme.label(15))
                        .foregroundStyle(Theme.canvas)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)
            }
        }
    }

    private var recapRenderKey: String {
        "\(selectedWeek.timeIntervalSinceReferenceDate)-\(logs.count)"
    }

    /// Tracks which week was "current" when the view last checked; used to
    /// tell "user was on this week" apart from "user browsed history".
    @State private var anchorWeek: Date = StatsEngine.startOfWeek(containing: .now)

    private func reanchorWeekIfStale() {
        let currentWeek = StatsEngine.startOfWeek(containing: .now)
        guard currentWeek != anchorWeek else { return }
        if selectedWeek == anchorWeek {
            // They were watching the live week — carry them forward.
            selectedWeek = currentWeek
        }
        anchorWeek = currentWeek
    }

    /// Week number by the USER'S calendar convention, sampled mid-week so a
    /// Sunday-first week start never lands in the previous ISO week (the
    /// confirmed off-by-one: ISO weekOfYear of a US Sunday is last week's).
    private func isoWeekNumber(of date: Date) -> Int {
        let midWeek = Calendar.current.date(byAdding: .day, value: 3, to: date) ?? date
        return Calendar.current.component(.weekOfYear, from: midWeek)
    }

    /// Renders the recap card to a shareable image at 3x scale.
    /// RecapCard is glass-free by design so this rasterizes faithfully.
    private func renderRecapImage() -> Image? {
        guard !logs.isEmpty else { return nil }
        let card = RecapCard(weekOf: selectedWeek, logs: logs)
            .frame(width: 380)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = false
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Theme.energyYellow.opacity(0.7))
                    .accessibilityHidden(true)
                Text(Copy.emptyStats)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Log a can. Watch it become a bar. Feel something.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }
}
