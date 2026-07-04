import Foundation
import SwiftData

/// Achievement wall. Raw values are persisted in `UserProfile.badges`,
/// so never rename a case once shipped.
enum Badge: String, CaseIterable, Identifiable {
    case firstScan
    case sevenDayStreak
    case thirtyDayStreak
    case hundredClub
    case flavorCompletionist
    case nightOwl
    case dozenWeek
    case weekendWarrior

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstScan: "First Scan"
        case .sevenDayStreak: "7-Day Streak"
        case .thirtyDayStreak: "30-Day Streak"
        case .hundredClub: "100 Club"
        case .flavorCompletionist: "Flavor Completionist"
        case .nightOwl: "Night Owl"
        case .dozenWeek: "Dozen Week"
        case .weekendWarrior: "Weekend Warrior"
        }
    }

    var icon: String {
        switch self {
        case .firstScan: "barcode.viewfinder"
        case .sevenDayStreak: "flame"
        case .thirtyDayStreak: "flame.fill"
        case .hundredClub: "trophy.fill"
        case .flavorCompletionist: "paintpalette.fill"
        case .nightOwl: "moon.stars.fill"
        case .dozenWeek: "12.circle.fill"
        case .weekendWarrior: "figure.run"
        }
    }

    var detail: String {
        switch self {
        case .firstScan: "Every legend starts with a beep."
        case .sevenDayStreak: "Seven straight days. The fridge knows your name."
        case .thirtyDayStreak: "Thirty days. Seek help. Or don't."
        case .hundredClub: "One hundred cans. A round number for a rounding heart rate."
        case .flavorCompletionist: "Eight flavors deep. Gotta sip 'em all."
        case .nightOwl: "Logged between midnight and 4am. Bold choice."
        case .dozenWeek: "Twelve in one week. That's a case. That's commitment."
        case .weekendWarrior: "Five cans in one weekend. Monday never stood a chance."
        }
    }

    /// Returns only badges earned right now that are NOT already
    /// recorded in `profile.badges`.
    static func evaluate(profile: UserProfile, logs: [CanLog]) -> [Badge] {
        allCases.filter { badge in
            !profile.badges.contains(badge.rawValue)
                && badge.isEarned(profile: profile, logs: logs)
        }
    }

    // MARK: Criteria

    private func isEarned(profile: UserProfile, logs: [CanLog]) -> Bool {
        switch self {
        case .firstScan:
            logs.contains { $0.source == .scan }
        case .sevenDayStreak:
            profile.streakCount >= 7
        case .thirtyDayStreak:
            profile.streakCount >= 30
        case .hundredClub:
            logs.count >= 100
        case .flavorCompletionist:
            Set(logs.compactMap { $0.sku?.flavor }).count >= 8
        case .nightOwl:
            logs.contains { Calendar.current.component(.hour, from: $0.timestamp) < 4 }
        case .dozenWeek:
            Self.maxWeekCount(logs) >= 12
        case .weekendWarrior:
            Self.maxWeekendCount(logs) >= 5
        }
    }

    // MARK: Helpers

    private static func maxWeekCount(_ logs: [CanLog]) -> Int {
        var counts: [Date: Int] = [:]
        for log in logs {
            counts[StatsEngine.startOfWeek(containing: log.timestamp), default: 0] += 1
        }
        return counts.values.max() ?? 0
    }

    /// Buckets weekend logs by their Saturday so one Saturday+Sunday pair
    /// counts as a single weekend regardless of the calendar's firstWeekday.
    private static func maxWeekendCount(_ logs: [CanLog]) -> Int {
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for log in logs where calendar.isDateInWeekend(log.timestamp) {
            let day = calendar.startOfDay(for: log.timestamp)
            let weekday = calendar.component(.weekday, from: day)
            // weekday 1 == Sunday: pair with the Saturday before it.
            let key = weekday == 1
                ? (calendar.date(byAdding: .day, value: -1, to: day) ?? day)
                : day
            counts[key, default: 0] += 1
        }
        return counts.values.max() ?? 0
    }
}
