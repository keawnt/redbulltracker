import Foundation
import SwiftData

// MARK: - CloudLeaderboardService

/// The real crew leaderboard — Supabase edition.
///
/// Strategy: push the last two weeks of local logs up as idempotent
/// `can_events` rows (same UUIDs both sides, duplicates ignored), then ask
/// the `crew_leaderboard` RPC for the standings. Week bounds are computed
/// HERE, from the user's own calendar (`StatsEngine.startOfWeek`), because
/// the server refuses to have opinions about when a week starts.
///
/// Every path that can't reach the cloud — placeholder config, signed out,
/// a crew that only exists locally, or any network/decode failure — falls
/// back to `MockLeaderboardService`. Nobody ever stares at a blank podium.
struct CloudLeaderboardService: LeaderboardService {

    // MARK: Entries

    func entries(crew: Crew?, myWeeklyCount: Int, myLastWeekCount: Int) async -> [LeaderboardEntry] {
        guard SupabaseConfig.isConfigured,
              let myUserID = SupabaseAuth.shared.userID,
              let serverID = crew?.serverID
        else {
            return await MockLeaderboardService().entries(
                crew: crew, myWeeklyCount: myWeeklyCount, myLastWeekCount: myLastWeekCount
            )
        }

        do {
            let token = try await SupabaseAuth.shared.validAccessToken()

            // Same calendar anchor the rest of the app lives by — Sunday
            // midnight in the US, Monday most other places.
            let calendar = Calendar.current
            let start = StatsEngine.startOfWeek(containing: .now)
            let end = calendar.date(byAdding: .day, value: 7, to: start)
                ?? start.addingTimeInterval(604_800)
            let prevStart = calendar.date(byAdding: .day, value: -7, to: start)
                ?? start.addingTimeInterval(-604_800)

            await syncRecentLogs(from: prevStart, to: end, userID: myUserID, accessToken: token)

            let data = try await SupabaseAPI.rpc(
                "crew_leaderboard",
                params: [
                    "p_crew": serverID.uuidString.lowercased(),
                    "p_start": Self.iso(start),
                    "p_end": Self.iso(end),
                    "p_prev_start": Self.iso(prevStart),
                    "p_prev_end": Self.iso(start),
                ],
                accessToken: token
            )

            let rows = try JSONDecoder().decode([CloudStandingRow].self, from: data)

            // Zero rows means the server doesn't consider us a member of
            // this crew (RLS said no). Blank podiums are against policy.
            guard !rows.isEmpty else {
                return await MockLeaderboardService().entries(
                    crew: crew, myWeeklyCount: myWeeklyCount, myLastWeekCount: myLastWeekCount
                )
            }

            return rows
                .map { row in
                    let isYou = row.userID == myUserID
                    return LeaderboardEntry(
                        id: row.userID,
                        name: isYou ? "You" : row.displayName,
                        weeklyCount: row.currentCount,
                        lastWeekDelta: row.currentCount - row.prevCount,
                        isYou: isYou,
                        flavorSummary: row.flavors
                    )
                }
                .sorted { lhs, rhs in
                    lhs.weeklyCount != rhs.weeklyCount
                        ? lhs.weeklyCount > rhs.weeklyCount
                        : lhs.name < rhs.name
                }
        } catch {
            print("CloudLeaderboardService: cloud standings failed, serving mock — \(error)")
            return await MockLeaderboardService().entries(
                crew: crew, myWeeklyCount: myWeeklyCount, myLastWeekCount: myLastWeekCount
            )
        }
    }

    // MARK: Crews

    /// `create_crew` mints the invite code server-side (same ambiguity-free
    /// alphabet the local generator uses) and enrolls the creator.
    func createCrew(name: String) async throws -> (serverID: UUID, inviteCode: String) {
        let token = try await SupabaseAuth.shared.validAccessToken()
        let data = try await SupabaseAPI.rpc(
            "create_crew", params: ["p_name": name], accessToken: token
        )
        guard let row = try JSONDecoder().decode([CreateCrewRow].self, from: data).first else {
            throw CloudCrewError.emptyReply
        }
        return (serverID: row.crewID, inviteCode: row.inviteCode)
    }

    /// `join_crew` resolves the code and answers with the crew's REAL name —
    /// no more everyone living in "THE PIT CREW".
    func joinCrew(code: String) async throws -> (serverID: UUID, name: String) {
        let token = try await SupabaseAuth.shared.validAccessToken()
        let data = try await SupabaseAPI.rpc(
            "join_crew", params: ["p_code": code], accessToken: token
        )
        guard let row = try JSONDecoder().decode([JoinCrewRow].self, from: data).first else {
            throw CloudCrewError.emptyReply
        }
        return (serverID: row.crewID, name: row.crewName)
    }

    // MARK: Sync

    /// Mirrors this week's and last week's local logs into `can_events`.
    /// Rows reuse the CanLog UUID, so re-sending is a server-side no-op
    /// (`on_conflict=id` + ignore-duplicates). Failures are logged and
    /// swallowed — a sync hiccup should never cost anyone the standings.
    private func syncRecentLogs(
        from windowStart: Date, to windowEnd: Date, userID: UUID, accessToken: String
    ) async {
        guard let container = CanCountApp.sharedContainer else { return }

        let descriptor = FetchDescriptor<CanLog>(
            predicate: #Predicate { $0.timestamp >= windowStart && $0.timestamp < windowEnd }
        )
        guard let logs = try? container.mainContext.fetch(descriptor), !logs.isEmpty else { return }

        let rows: [[String: Any]] = logs.map { log in
            let lineup = log.sku?.lineup ?? "original"
            return [
                "id": log.id.uuidString.lowercased(),
                "user_id": userID.uuidString.lowercased(),
                "logged_at": Self.iso(log.timestamp),
                "flavor": log.sku?.flavor ?? "Unknown",
                // Pre-lineup SKUs carry "" until SeedLoader heals them;
                // the server default is "original", so say that instead.
                "lineup": lineup.isEmpty ? "original" : lineup,
                "caffeine_mg": log.sku?.caffeineMG ?? 0,
            ]
        }

        do {
            try await SupabaseAPI.insert(
                table: "can_events", rows: rows, accessToken: accessToken, onConflict: "id"
            )
        } catch {
            print("CloudLeaderboardService: can_events sync failed — \(error)")
        }
    }

    // MARK: Helpers

    /// ISO8601 with fractional seconds — exactly what timestamptz expects.
    /// (Formatter built per call: ISO8601DateFormatter isn't Sendable, and
    /// this runs a handful of times per sync — not worth unsafe sharing.)
    private nonisolated static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Errors

/// Thrown when an RPC that promises exactly one row hands back none.
nonisolated enum CloudCrewError: Error {
    case emptyReply
}

// MARK: - Wire format (private)

/// One member's standing from `crew_leaderboard`.
private nonisolated struct CloudStandingRow: Decodable {
    let userID: UUID
    let displayName: String
    let currentCount: Int
    let prevCount: Int
    let flavors: [String: Int]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case displayName = "display_name"
        case currentCount = "current_count"
        case prevCount = "prev_count"
        case flavors
    }
}

private nonisolated struct CreateCrewRow: Decodable {
    let crewID: UUID
    let inviteCode: String

    enum CodingKeys: String, CodingKey {
        case crewID = "crew_id"
        case inviteCode = "invite_code"
    }
}

private nonisolated struct JoinCrewRow: Decodable {
    let crewID: UUID
    let crewName: String

    enum CodingKeys: String, CodingKey {
        case crewID = "crew_id"
        case crewName = "crew_name"
    }
}
