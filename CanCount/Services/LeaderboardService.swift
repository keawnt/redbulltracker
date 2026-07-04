import Foundation

// MARK: - LeaderboardEntry

struct LeaderboardEntry: Identifiable, Equatable {
    let id: UUID
    let name: String
    let weeklyCount: Int
    let lastWeekDelta: Int
    let isYou: Bool
    let flavorSummary: [String: Int]
}

// MARK: - LeaderboardService

protocol LeaderboardService {
    func entries(crew: Crew?, myWeeklyCount: Int) async -> [LeaderboardEntry]
}

// MARK: - MockLeaderboardService

/// Deterministic fake crew.
///
/// CLOUDKIT SWAP POINT: replace this with a `CloudKitLeaderboardService`
/// conforming to `LeaderboardService` that reads weekly aggregate records
/// from the crew's shared CloudKit zone (crew membership via CKShare,
/// Sign in with Apple gating handled in LeaderboardView). Nothing upstream
/// changes — the view only knows the protocol.
struct MockLeaderboardService: LeaderboardService {

    private struct Friend {
        let id: UUID
        let name: String
        let seed: Int
        let flavors: [String]
    }

    private static let youID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // Stable IDs so springy reorders animate identity, not replacement.
    private static let friends: [Friend] = [
        Friend(id: UUID(uuidString: "A1A1A1A1-0000-0000-0000-000000000001")!,
               name: "Lindsay", seed: 7, flavors: ["Tropical", "Original"]),
        Friend(id: UUID(uuidString: "A1A1A1A1-0000-0000-0000-000000000002")!,
               name: "Marcus", seed: 13, flavors: ["Original", "Sugarfree"]),
        Friend(id: UUID(uuidString: "A1A1A1A1-0000-0000-0000-000000000003")!,
               name: "Priya", seed: 17, flavors: ["Watermelon", "Tropical", "Açaí"]),
        Friend(id: UUID(uuidString: "A1A1A1A1-0000-0000-0000-000000000004")!,
               name: "Dex", seed: 23, flavors: ["Zero", "Blueberry"]),
        Friend(id: UUID(uuidString: "A1A1A1A1-0000-0000-0000-000000000005")!,
               name: "Sam", seed: 29, flavors: ["Original"]),
        Friend(id: UUID(uuidString: "A1A1A1A1-0000-0000-0000-000000000006")!,
               name: "Noor", seed: 31, flavors: ["Coconut", "Peach", "Sugarfree"]),
    ]

    func entries(crew: Crew?, myWeeklyCount: Int) async -> [LeaderboardEntry] {
        let week = Calendar(identifier: .iso8601).component(.weekOfYear, from: .now)

        var all = Self.friends.map { friend in
            let current = Self.weeklyCount(seed: friend.seed, week: week)
            let previous = Self.weeklyCount(seed: friend.seed, week: week - 1)
            return LeaderboardEntry(
                id: friend.id,
                name: friend.name,
                weeklyCount: current,
                lastWeekDelta: current - previous,
                isYou: false,
                flavorSummary: Self.flavorSummary(total: current, flavors: friend.flavors)
            )
        }

        all.append(LeaderboardEntry(
            id: Self.youID,
            name: "You",
            weeklyCount: myWeeklyCount,
            lastWeekDelta: 0,
            isYou: true,
            flavorSummary: [:]
        ))

        return all.sorted { lhs, rhs in
            lhs.weeklyCount != rhs.weeklyCount
                ? lhs.weeklyCount > rhs.weeklyCount
                : lhs.name < rhs.name
        }
    }

    // MARK: Deterministic numbers

    /// Counts derive purely from the ISO week number — no randomness at
    /// runtime, so ranks hold steady all week and reshuffle at the reset.
    private static func weeklyCount(seed: Int, week: Int) -> Int {
        let raw = seed &* (week &+ 11) &+ (seed &* seed)
        return 3 + ((raw % 14) + 14) % 14 // 3...16 cans
    }

    /// Distributes a weekly total across a friend's signature flavors
    /// (front-loaded weights, remainder to the last) so it always sums
    /// exactly to `total`.
    private static func flavorSummary(total: Int, flavors: [String]) -> [String: Int] {
        guard total > 0, !flavors.isEmpty else { return [:] }
        let weights = (0..<flavors.count).map { flavors.count - $0 }
        let weightSum = weights.reduce(0, +)

        var summary: [String: Int] = [:]
        var remaining = total
        for (index, flavor) in flavors.enumerated() {
            let share = index == flavors.count - 1
                ? remaining
                : total * weights[index] / weightSum
            if share > 0 { summary[flavor] = share }
            remaining -= share
        }
        return summary
    }
}
