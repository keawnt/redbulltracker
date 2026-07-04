import SwiftUI
import SwiftData

/// Home ("Today") tab — the hero screen of CanCount.
///
/// One hero element: the giant weekly-count numeral, odometer-rolling up from 0
/// on every appearance. The week's most-logged flavor floats behind it. Glass
/// stat pills and the last five sips cascade in beneath with staggered springs.
/// Everything degrades to crossfades (or nothing) under Reduce Motion.
struct HomeView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \CanLog.timestamp, order: .reverse) private var logs: [CanLog]

    @State private var profile: UserProfile?
    @State private var displayedWeekCount = 0
    @State private var revealed = false
    @State private var confettiTrigger = 0
    @State private var showManualLog = false
    @State private var showPRBanner = false
    @State private var prBannerToken = 0

    init() {}

    // MARK: - Derived stats

    private var weekCount: Int { StatsEngine.weekCount(logs, weekOf: .now) }
    private var todayCount: Int { StatsEngine.todayCount(logs) }
    private var todayCaffeine: Int { StatsEngine.todayCaffeine(logs) }
    private var streak: Int { profile?.streakCount ?? 0 }
    private var recentLogs: [CanLog] { Array(logs.prefix(5)) }

    /// The week's most-logged flavor. Falls back to all-time logs, then nil
    /// (CanArtwork renders the silver/blue original for nil).
    private var heroSKU: SKU? {
        let weekLogs = StatsEngine.logs(logs, inWeekOf: .now)
        let pool = weekLogs.isEmpty ? logs : weekLogs
        var counts: [String: Int] = [:]
        for log in pool {
            if let flavor = log.sku?.flavor {
                counts[flavor, default: 0] += 1
            }
        }
        guard let topFlavor = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return pool.first { $0.sku?.flavor == topFlavor }?.sku
    }

    private var caffeineOverLimit: Bool {
        guard let profile else { return false }
        return todayCaffeine > profile.caffeineWarningMG
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                heroSection

                pillsSection

                if caffeineOverLimit {
                    caffeineBanner
                        .transition(.opacity)
                }

                recentSection

                manualLogButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 140) // clearance for the floating scan button + tab bar
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring, value: caffeineOverLimit)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .overlay {
            ConfettiBurst(trigger: confettiTrigger)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if showPRBanner {
                prBanner
            }
        }
        .sheet(isPresented: $showManualLog) {
            ManualLogSheet()
        }
        .sensoryFeedback(.success, trigger: confettiTrigger)
        .onAppear(perform: handleAppear)
        .onChange(of: logs.count) { oldCount, newCount in
            handleLogsChanged(from: oldCount, to: newCount)
        }
    }

    // MARK: - Header (greeting left, streak pill right)

    private var header: some View {
        HStack(alignment: .center) {
            Text(Copy.greeting())
                .font(Theme.label(14))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            streakPill
        }
    }

    private var streakPill: some View {
        HStack(spacing: 5) {
            Text("🔥")
                .font(.system(size: 14))
            Text("\(streak)")
                .font(Theme.label(15))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(Theme.bullRed.opacity(0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak) day streak")
    }

    // MARK: - Hero (the one big thing)

    private var heroSection: some View {
        ZStack(alignment: .leading) {
            // The week's flavor floats behind and to the right of the numeral.
            HStack {
                Spacer()
                CanArtwork(sku: heroSKU, height: 240, floating: true)
                    .opacity(0.95)
                    .offset(x: 16, y: 6)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("\(displayedWeekCount)")
                    .font(Theme.heroFont(120))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(displayedWeekCount)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .shadow(color: Theme.energyYellow.opacity(0.18), radius: 32, y: 6)
                MicroLabel(text: "Cans this week")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(weekCount) cans this week")
        }
        .padding(.top, 8)
    }

    // MARK: - Stat pills

    private var pillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StatPill(
                    title: "Today",
                    value: "\(todayCount)",
                    accent: Theme.energyYellow,
                    systemImage: "cylinder.fill"
                )
                .cascadeIn(1, revealed: revealed)
                .accessibilityLabel("\(todayCount) cans today")

                StatPill(
                    title: "Caffeine",
                    value: "\(todayCaffeine)mg",
                    accent: Theme.racingBlue,
                    systemImage: "bolt.fill"
                )
                .cascadeIn(2, revealed: revealed)
                .accessibilityLabel("\(todayCaffeine) milligrams of caffeine today")

                StatPill(
                    title: "Streak",
                    value: "\(streak)",
                    accent: Theme.bullRed,
                    systemImage: "flame.fill"
                )
                .cascadeIn(3, revealed: revealed)
                .accessibilityLabel("\(streak) day streak")
            }

            Text(Copy.todayLine(count: todayCount))
                .font(Theme.label(12))
                .foregroundStyle(.white.opacity(0.5))
                .cascadeIn(4, revealed: revealed)
        }
    }

    // MARK: - Caffeine banner (gentle, never preachy)

    private var caffeineBanner: some View {
        GlassCard(tint: Theme.bullRed) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.bullRed)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(todayCaffeine)mg of caffeine today.")
                        .font(Theme.label(14))
                        .foregroundStyle(.white)
                    Text("That's past your \(profile?.caffeineWarningMG ?? 400)mg line. Water is also a beverage.")
                        .font(Theme.label(12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recent sips

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MicroLabel(text: "Recent sips")

            if recentLogs.isEmpty {
                emptyRecents
                    .cascadeIn(5, revealed: revealed)
            } else {
                ForEach(Array(recentLogs.enumerated()), id: \.element.id) { index, log in
                    recentRow(log)
                        .cascadeIn(5 + index, revealed: revealed)
                }
            }
        }
    }

    private var emptyRecents: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "refrigerator")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.energyYellow.opacity(0.8))
                    .accessibilityHidden(true)
                Text(Copy.emptyRecents)
                    .font(Theme.label(13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }

    private func recentRow(_ log: CanLog) -> some View {
        GlassCard(radius: 20) {
            HStack(spacing: 12) {
                if let sku = log.sku {
                    CanChip(sku: sku)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.silver.opacity(0.4))
                        .frame(width: 18, height: 26)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.sku?.flavor ?? "Mystery can")
                        .font(Theme.label(14))
                        .foregroundStyle(.white)
                    if let sizeLabel = log.sku?.sizeLabel {
                        Text(sizeLabel)
                            .font(Theme.label(11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 8)
                Text(timeLabel(for: log.timestamp))
                    .font(Theme.label(11))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Manual log ("Can already recycled?")

    private var manualLogButton: some View {
        HStack {
            Spacer()
            Button {
                showManualLog = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.3.trianglepath")
                    Text("Can already recycled?")
                }
                .font(Theme.label(13))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Log a can manually")
            Spacer()
        }
        .cascadeIn(10, revealed: revealed)
    }

    // MARK: - PR banner

    private var prBanner: some View {
        HStack(spacing: 8) {
            Text("🏆")
            Text(Copy.newPR)
                .font(Theme.label(14))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Theme.energyYellow.opacity(0.5)))
        .padding(.top, 6)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.newPR)
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        if profile == nil {
            profile = UserProfile.current(in: modelContext)
        }

        let target = weekCount
        if reduceMotion {
            displayedWeekCount = target
            revealed = true
            return
        }

        // Odometer count-up from 0 on every appearance.
        displayedWeekCount = 0
        revealed = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(Theme.spring) {
                displayedWeekCount = weekCount
            }
        }
    }

    private func handleLogsChanged(from oldCount: Int, to newCount: Int) {
        let target = weekCount
        if reduceMotion {
            displayedWeekCount = target
        } else {
            withAnimation(Theme.spring) {
                displayedWeekCount = target
            }
        }

        // Only celebrate when a log was ADDED and this week is now a record.
        guard newCount > oldCount else { return }
        if StatsEngine.isPersonalRecordWeek(logs, weekOf: .now) {
            celebratePR()
        }
    }

    private func celebratePR() {
        confettiTrigger += 1
        if reduceMotion {
            showPRBanner = true
        } else {
            withAnimation(Theme.spring) {
                showPRBanner = true
            }
        }

        prBannerToken += 1
        let token = prBannerToken
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard token == prBannerToken else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring) {
                showPRBanner = false
            }
        }
    }

    // MARK: - Formatting

    private func timeLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }
}

// MARK: - Staggered cascade-in

/// Fades + slides content in with a per-index spring delay once `revealed`
/// flips true. Under Reduce Motion this becomes a plain, undelayed crossfade.
private struct CascadeIn: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let index: Int
    let revealed: Bool

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 22)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.25)
                    : Theme.spring.delay(Double(index) * 0.07),
                value: revealed
            )
    }
}

extension View {
    fileprivate func cascadeIn(_ index: Int, revealed: Bool) -> some View {
        modifier(CascadeIn(index: index, revealed: revealed))
    }
}
