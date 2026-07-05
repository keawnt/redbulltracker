import Foundation
import SwiftData

// MARK: - UserProfile singleton access

extension UserProfile {
    /// Fetch-or-create the single local profile. Always returns an inserted model.
    static func current(in context: ModelContext) -> UserProfile {
        var descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.joinDate, order: .forward)]
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        return profile
    }
}

// MARK: - LogResult

struct LogResult {
    let log: CanLog
    let newBadges: [Badge]
    let isPersonalRecord: Bool
    /// Whether context.save() actually succeeded. When false the UI must not
    /// celebrate — the can never made it to disk.
    let persisted: Bool
}

// MARK: - LogPipeline

/// The one true way a can enters the database. Inserts the log, keeps the
/// streak honest, hands out badges, and reports whether this week just became
/// a personal record.
enum LogPipeline {

    @discardableResult
    static func log(sku: SKU, source: LogSource, context: ModelContext) -> LogResult {
        let entry = CanLog(sku: sku, source: source)
        context.insert(entry)

        let profile = UserProfile.current(in: context)
        updateStreak(profile: profile, logDate: entry.timestamp)

        var allLogs = (try? context.fetch(FetchDescriptor<CanLog>())) ?? []
        if !allLogs.contains(where: { $0.id == entry.id }) {
            allLogs.append(entry)
        }

        let newBadges = Badge.evaluate(profile: profile, logs: allLogs)
        profile.badges.append(contentsOf: newBadges.map(\.rawValue))

        // Crossing moment only — one celebration per broken record, not one
        // per log for the rest of a record week.
        let isPersonalRecord = StatsEngine.becamePersonalRecord(allLogs, weekOf: entry.timestamp)

        var persisted = true
        do {
            try context.save()
        } catch {
            persisted = false
        }

        return LogResult(log: entry, newBadges: newBadges, isPersonalRecord: isPersonalRecord, persisted: persisted)
    }

    // MARK: Streak

    /// Same-day log: streak unchanged. Logged yesterday: +1.
    /// First log ever or a gap: reset to 1. Always stamps `lastLogDate`.
    private static func updateStreak(profile: UserProfile, logDate: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: logDate)

        if let last = profile.lastLogDate {
            let lastDay = calendar.startOfDay(for: last)
            if lastDay == today {
                profile.streakCount = max(profile.streakCount, 1)
            } else if calendar.date(byAdding: .day, value: 1, to: lastDay) == today {
                profile.streakCount += 1
            } else {
                profile.streakCount = 1
            }
        } else {
            profile.streakCount = 1
        }

        profile.lastLogDate = logDate
    }
}
