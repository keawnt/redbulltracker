import Foundation
import SwiftData
import SwiftUI

// MARK: - Stat value types

struct DayStat: Identifiable {
    let day: Date
    let count: Int
    let caffeineMG: Int
    let dominantAccent: Color
    var id: Date { day }
}

struct FlavorSlice: Identifiable {
    let flavor: String
    let count: Int
    let accent: Color
    var id: String { flavor }
}

struct LifetimeStats {
    let cans: Int
    let liters: Double
    let caffeineMG: Int
    /// One espresso ≈ 63mg. Absurd equivalents are load-bearing here.
    var espressos: Int { caffeineMG / 63 }
}

// MARK: - StatsEngine

/// Pure derivations over `[CanLog]`. Never stores anything.
/// A log whose `sku` relationship is nil counts as 0 caffeine / 0 mL and
/// the flavor "Unknown" with a silver accent.
enum StatsEngine {

    // MARK: Week math

    /// Start of the week containing `date`, respecting the user's calendar
    /// (`Calendar.current.firstWeekday` — Sunday in the US, Monday elsewhere).
    static func startOfWeek(containing date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func logs(_ logs: [CanLog], inWeekOf date: Date) -> [CanLog] {
        let start = startOfWeek(containing: date)
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return [] }
        return logs.filter { $0.timestamp >= start && $0.timestamp < end }
    }

    // MARK: Today

    static func todayCount(_ logs: [CanLog]) -> Int {
        logs.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    static func todayCaffeine(_ logs: [CanLog]) -> Int {
        logs.filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + ($1.sku?.caffeineMG ?? 0) }
    }

    // MARK: Weekly

    static func weekCount(_ logs: [CanLog], weekOf date: Date) -> Int {
        StatsEngine.logs(logs, inWeekOf: date).count
    }

    /// Exactly 7 entries, zero-filled, one per day of the week containing `date`.
    static func dailyStats(_ logs: [CanLog], weekOf date: Date) -> [DayStat] {
        let calendar = Calendar.current
        let start = startOfWeek(containing: date)
        let weekLogs = StatsEngine.logs(logs, inWeekOf: date)
        let byDay = Dictionary(grouping: weekLogs) { calendar.startOfDay(for: $0.timestamp) }

        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)
                ?? start.addingTimeInterval(TimeInterval(offset) * 86_400)
            let dayLogs = byDay[calendar.startOfDay(for: day)] ?? []
            return DayStat(
                day: day,
                count: dayLogs.count,
                caffeineMG: dayLogs.reduce(0) { $0 + ($1.sku?.caffeineMG ?? 0) },
                dominantAccent: dominantAccent(of: dayLogs)
            )
        }
    }

    // MARK: Flavors

    /// One slice per distinct flavor, sorted descending by count
    /// (alphabetical tiebreak so the ordering is stable).
    static func flavorBreakdown(_ logs: [CanLog]) -> [FlavorSlice] {
        var counts: [String: (count: Int, accent: Color)] = [:]
        for log in logs {
            let flavor = log.sku?.flavor ?? "Unknown"
            let accent = log.sku?.accent ?? Theme.silver
            counts[flavor, default: (0, accent)].count += 1
        }
        return counts
            .map { FlavorSlice(flavor: $0.key, count: $0.value.count, accent: $0.value.accent) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.flavor < rhs.flavor
            }
    }

    // MARK: Lifetime

    static func lifetime(_ logs: [CanLog]) -> LifetimeStats {
        let totalML = logs.reduce(0) { $0 + ($1.sku?.sizeML ?? 0) }
        let totalCaffeine = logs.reduce(0) { $0 + ($1.sku?.caffeineMG ?? 0) }
        return LifetimeStats(cans: logs.count, liters: Double(totalML) / 1_000, caffeineMG: totalCaffeine)
    }

    // MARK: Personality

    /// Assigns a flavor personality from a breakdown.
    /// Rules: <5 lifetime cans = ROOKIE; 80%+ sugar-free = SUGARFREE PURIST;
    /// 60%+ one flavor = <FLAVOR> LOYALIST; 6+ flavors with no majority = CHAOS AGENT.
    static func personality(_ slices: [FlavorSlice]) -> (title: String, line: String) {
        let total = slices.reduce(0) { $0 + $1.count }
        guard total >= 5, !slices.isEmpty else {
            return ("ROOKIE", "Not enough data to judge you. Yet.")
        }

        let sorted = slices.sorted { $0.count > $1.count }
        let top = sorted[0]
        let topShare = Double(top.count) / Double(total)

        let sugarFreeCount = slices
            .filter { isSugarFreeFlavor($0.flavor) }
            .reduce(0) { $0 + $1.count }
        if Double(sugarFreeCount) / Double(total) >= 0.8 {
            return ("SUGARFREE PURIST", "All of the wings, none of the sugar. Discipline is a flavor.")
        }

        if topShare >= 0.6 {
            return ("\(top.flavor.uppercased()) LOYALIST",
                    "\(top.flavor). Every time. The commitment has been noted.")
        }

        if slices.count >= 6, topShare <= 0.5 {
            return ("CHAOS AGENT", "Six-plus flavors, zero loyalty. The fridge fears you.")
        }

        return ("STEADY OPERATOR", "A rotation, but a sensible one. Respectable.")
    }

    // MARK: Personal records

    /// True when the week containing `date` has strictly more cans than
    /// every prior week — and there IS a prior week with logs. A brand-new
    /// user's first week is never a "record"; records require a past to beat.
    static func isPersonalRecordWeek(_ logs: [CanLog], weekOf date: Date) -> Bool {
        let thisWeekStart = startOfWeek(containing: date)
        let weekCounts = weeklyCounts(of: logs)
        guard let thisCount = weekCounts[thisWeekStart], thisCount > 0 else { return false }
        let prior = weekCounts.filter { $0.key < thisWeekStart }.values
        guard let priorBest = prior.max(), priorBest > 0 else { return false }
        return thisCount > priorBest
    }

    /// True ONLY at the crossing moment: a prior best exists and this week's
    /// count just reached priorBest + 1. Use this to fire celebrations exactly
    /// once instead of on every log of a record week.
    static func becamePersonalRecord(_ logs: [CanLog], weekOf date: Date) -> Bool {
        let thisWeekStart = startOfWeek(containing: date)
        let weekCounts = weeklyCounts(of: logs)
        guard let thisCount = weekCounts[thisWeekStart], thisCount > 0 else { return false }
        let prior = weekCounts.filter { $0.key < thisWeekStart }.values
        guard let priorBest = prior.max(), priorBest > 0 else { return false }
        return thisCount == priorBest + 1
    }

    // MARK: Streak (live, from the logs — never trusts stored counters)

    /// Consecutive calendar days with at least one log, counting the run that
    /// ends today or yesterday (yesterday keeps a streak "alive" until the
    /// day is actually missed). 0 when the last log is older than yesterday.
    static func currentStreak(_ logs: [CanLog], asOf now: Date = .now) -> Int {
        let calendar = Calendar.current
        let days = Set(logs.map { calendar.startOfDay(for: $0.timestamp) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        var anchor: Date
        if days.contains(today) {
            anchor = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  days.contains(yesterday) {
            anchor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(anchor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: anchor) else { break }
            anchor = previous
        }
        return streak
    }

    // MARK: Lineups

    /// Breakdown of logs by Red Bull family (Original / Sugarfree / Zero /
    /// Editions), reusing FlavorSlice with the lineup label in `flavor`.
    static func lineupBreakdown(_ logs: [CanLog]) -> [FlavorSlice] {
        let accents: [String: Color] = [
            "Original": Theme.silver,
            "Sugarfree": Theme.racingBlue,
            "Zero": Color(hex: "#7C8794"),
            "Editions": Theme.energyYellow,
        ]
        var counts: [String: Int] = [:]
        for log in logs {
            counts[log.sku?.lineupLabel ?? "Original", default: 0] += 1
        }
        return counts
            .map { FlavorSlice(flavor: $0.key, count: $0.value, accent: accents[$0.key] ?? Theme.silver) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.flavor < $1.flavor }
    }

    private static func weeklyCounts(of logs: [CanLog]) -> [Date: Int] {
        var weekCounts: [Date: Int] = [:]
        for log in logs {
            weekCounts[startOfWeek(containing: log.timestamp), default: 0] += 1
        }
        return weekCounts
    }

    // MARK: Private helpers

    private static func dominantAccent(of logs: [CanLog]) -> Color {
        guard !logs.isEmpty else { return Theme.silver }
        var counts: [String: (count: Int, accent: Color)] = [:]
        for log in logs {
            let flavor = log.sku?.flavor ?? "Unknown"
            let accent = log.sku?.accent ?? Theme.silver
            counts[flavor, default: (0, accent)].count += 1
        }
        // Deterministic winner: highest count, alphabetical-first flavor on ties.
        let winner = counts.max { lhs, rhs in
            lhs.value.count != rhs.value.count
                ? lhs.value.count < rhs.value.count
                : lhs.key > rhs.key
        }
        return winner?.value.accent ?? Theme.silver
    }

    private static func isSugarFreeFlavor(_ flavor: String) -> Bool {
        let lowered = flavor.lowercased()
        return lowered.contains("sugarfree")
            || lowered.contains("sugar free")
            || lowered.contains("sugar-free")
            || lowered.contains("zero")
    }
}
