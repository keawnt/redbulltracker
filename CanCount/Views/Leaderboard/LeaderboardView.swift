import SwiftUI
import SwiftData
import Combine
import Foundation
import AuthenticationServices

// MARK: - LeaderboardView

/// The Crews tab. Podium up top, full standings below, dry trash talk throughout.
struct LeaderboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var crews: [Crew]
    @Query private var logs: [CanLog]

    @State private var entries: [LeaderboardEntry] = []
    @State private var selectedFriend: LeaderboardEntry?
    @State private var showingJoinSheet = false
    @State private var showingFindFriends = false
    @State private var weekAnchor: Date = .now
    @State private var toast: String?

    @Namespace private var podiumNamespace

    // CloudLeaderboardService reads real standings from Supabase when a crew
    // has a serverID and you're signed in — and self-falls-back to the mock
    // crew otherwise, so the local-only experience is byte-for-byte the same.
    private let service: any LeaderboardService = CloudLeaderboardService()

    init() {}

    private var crew: Crew? { crews.first }

    private var myWeeklyCount: Int {
        StatsEngine.weekCount(logs, weekOf: weekAnchor)
    }

    /// Your count for the week before this one — 7 days behind the same
    /// `startOfWeek` anchor, so both weeks live on the same calendar.
    private var myLastWeekCount: Int {
        let thisWeekStart = StatsEngine.startOfWeek(containing: weekAnchor)
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: thisWeekStart)
            ?? thisWeekStart.addingTimeInterval(-604_800)
        return StatsEngine.weekCount(logs, weekOf: lastWeek)
    }

    /// Last week's champion keeps the crown all week, wherever they now stand.
    /// Last week's count is reconstructed as `weeklyCount - lastWeekDelta`;
    /// ties break alphabetically, and nobody reigns over an empty week.
    private var reigningChampionID: UUID? {
        let champion = entries.max { lhs, rhs in
            let l = lhs.weeklyCount - lhs.lastWeekDelta
            let r = rhs.weeklyCount - rhs.lastWeekDelta
            return l != r ? l < r : lhs.name > rhs.name
        }
        guard let champion, champion.weeklyCount - champion.lastWeekDelta > 0 else { return nil }
        return champion.id
    }

    /// Reduce Motion: springs become gentle crossfade-ish eases.
    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : Theme.spring
    }

    private var refreshKey: LBRefreshKey {
        LBRefreshKey(
            weekStart: StatsEngine.startOfWeek(containing: weekAnchor),
            myCount: myWeeklyCount,
            myLastCount: myLastWeekCount,
            crewID: crew?.id
        )
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            if let crew {
                crewContent(crew)
            } else {
                emptyState
            }
        }
        // Loads on appear, on week rollover, on crew creation, and whenever my count changes.
        .task(id: refreshKey) {
            let loaded = await service.entries(
                crew: crew,
                myWeeklyCount: myWeeklyCount,
                myLastWeekCount: myLastWeekCount
            )
            withAnimation(motion) {
                entries = loaded
            }
        }
        // Week-change detection: day-change notifications re-anchor the week; the
        // refreshKey's weekStart only actually changes when the calendar's week
        // rolls over (Sunday midnight in the US, Monday most other places).
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSCalendarDayChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            weekAnchor = .now
        }
        .sheet(item: $selectedFriend) { friend in
            LBFriendDetailSheet(entry: friend)
        }
        .sheet(isPresented: $showingJoinSheet) {
            LBJoinCrewSheet { message in
                showToast(message)
            }
        }
        .sheet(isPresented: $showingFindFriends) {
            FindFriendsSheet()
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(Theme.label(12))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 110) // clear the floating scan button
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: entries)
    }

    /// One-line glass toast at the bottom; clears itself unless a newer
    /// message has already taken the slot.
    private func showToast(_ message: String) {
        withAnimation(motion) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == message {
                withAnimation(motion) { toast = nil }
            }
        }
    }

    // MARK: Crew content

    private func crewContent(_ crew: Crew) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(crew)
                if entries.isEmpty {
                    loadingState
                } else {
                    podium
                    rankedList
                    footer
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120) // stay clear of the floating scan button
        }
        .scrollIndicators(.hidden)
    }

    private func header(_ crew: Crew) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "LEADERBOARD")
            Text(crew.name)
                .font(Theme.heroFont(40))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 12) {
                MicroLabel(text: "INVITE CODE")
                Text(crew.inviteCode)
                    .font(Theme.label(15))
                    .kerning(3)
                    .foregroundStyle(Theme.energyYellow)
                ShareLink(
                    item: "Join my CanCount crew \"\(crew.name)\" — code \(crew.inviteCode). Bring your own cans."
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Share invite code")
                if SupabaseConfig.isConfigured && SupabaseAuth.shared.isSignedIn {
                    Button {
                        Haptics.tick()
                        showingFindFriends = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Find friends")
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Theme.energyYellow)
            Text("Tallying cans. Checking receipts.")
                .font(Theme.label(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: Podium

    private var podiumSlots: [LBPodiumSlot] {
        let top = entries.prefix(3).enumerated().map { LBPodiumSlot(entry: $0.element, rank: $0.offset + 1) }
        // Display order: silver left, gold center, bronze right.
        var ordered: [LBPodiumSlot] = []
        if top.count > 1 { ordered.append(top[1]) }
        if !top.isEmpty { ordered.append(top[0]) }
        if top.count > 2 { ordered.append(top[2]) }
        return ordered
    }

    private var podium: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 14) {
                ForEach(podiumSlots) { slot in
                    LBPodiumColumn(
                        entry: slot.entry,
                        rank: slot.rank,
                        isReigningChampion: slot.entry.id == reigningChampionID,
                        namespace: podiumNamespace,
                        reduceMotion: reduceMotion
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .animation(motion, value: entries)
        }
    }

    // MARK: Ranked list

    private var rankedList: some View {
        VStack(alignment: .leading, spacing: 12) {
            MicroLabel(text: "FULL STANDINGS")
            ForEach(entries) { entry in
                row(entry: entry, rank: rank(of: entry))
            }
        }
        .animation(motion, value: entries)
    }

    private func rank(of entry: LeaderboardEntry) -> Int {
        (entries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
    }

    @ViewBuilder
    private func row(entry: LeaderboardEntry, rank: Int) -> some View {
        // The podium already crowns top-3 champions; the list crown only
        // marks a reigning champion who has slipped out of the top three.
        let crowned = entry.id == reigningChampionID && rank > 3
        if entry.isYou {
            LBRankRow(entry: entry, rank: rank, isReigningChampion: crowned)
        } else {
            Button {
                Haptics.tick()
                selectedFriend = entry
            } label: {
                LBRankRow(entry: entry, rank: rank, isReigningChampion: crowned)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows their flavor breakdown")
        }
    }

    // MARK: Footer

    private var chaseLine: String? {
        guard let myIndex = entries.firstIndex(where: { $0.isYou }) else { return nil }
        guard myIndex < entries.count - 1 else {
            return "Nobody behind you. Start worrying about the people ahead."
        }
        let chaser = entries[myIndex + 1]
        let gap = entries[myIndex].weeklyCount - chaser.weeklyCount
        if gap <= 0 {
            return "\(chaser.name) is tied with you. Unacceptable."
        }
        return "\(chaser.name) is \(gap) can\(gap == 1 ? "" : "s") behind you. Stay ahead."
    }

    /// Names the actual reset day from the user's calendar — "Sunday" in the
    /// US, "Monday" most other places — so the footer never lies about it.
    private var resetLine: String {
        let calendar = Calendar.current
        let symbols = calendar.weekdaySymbols
        let index = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
        return "Resets \(symbols[index]) midnight"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel(text: resetLine)
            if let line = chaseLine {
                Text(line)
                    .font(Theme.label(13))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: Empty state (no crew)

    private var emptyState: some View {
        VStack(spacing: 18) {
            Text("🏆")
                .font(.system(size: 56))
                .padding(28)
                .glassEffect(.regular.tint(Theme.energyYellow.opacity(0.15)), in: .circle)
                .accessibilityHidden(true)
            Text(Copy.emptyLeaderboard)
                .font(Theme.heroFont(26))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("Assemble the crew. Establish dominance.")
                .font(Theme.label(14))
                .foregroundStyle(.white.opacity(0.5))
            if SupabaseConfig.isConfigured && !SupabaseAuth.shared.isSignedIn {
                signInCard
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
            }
            VStack(spacing: 12) {
                Button {
                    createCrew()
                } label: {
                    Text("CREATE CREW")
                        .font(Theme.label(15))
                        .kerning(1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)
                .foregroundStyle(.black)
                Button {
                    showingJoinSheet = true
                } label: {
                    Text("JOIN WITH CODE")
                        .font(Theme.label(15))
                        .kerning(1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 8)
            .padding(.horizontal, 32)
        }
        .padding(.horizontal, 24)
    }

    /// Signed-out pitch shown only when a real Supabase project is configured
    /// — with the placeholder key this card never exists.
    private var signInCard: some View {
        GlassCard(radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                MicroLabel(text: "REAL RIVALS")
                Text("Crews sync between phones once you sign in.")
                    .font(Theme.label(13))
                    .foregroundStyle(.white.opacity(0.7))
                SignInWithAppleButton(.signIn) { request in
                    SupabaseAuth.shared.configure(request: request)
                } onCompletion: { result in
                    Task { try? await SupabaseAuth.shared.completeSignIn(with: result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .clipShape(.capsule)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Signed in against a live Supabase project → the crew is minted
    /// server-side (server invite code, serverID on the local row).
    /// Anything else — placeholder config, signed out, or the cloud flaking —
    /// lands on exactly the classic local-only crew.
    private func createCrew() {
        let name = "THE PIT CREW"
        guard SupabaseConfig.isConfigured, SupabaseAuth.shared.isSignedIn else {
            insertLocalCrew(name: name, code: Self.makeInviteCode())
            return
        }
        Task {
            do {
                let created = try await CloudLeaderboardService().createCrew(name: name)
                let crew = Crew(name: name, inviteCode: created.inviteCode)
                crew.serverID = created.serverID
                modelContext.insert(crew)
                try? modelContext.save()
                Haptics.success()
            } catch {
                insertLocalCrew(name: name, code: Self.makeInviteCode())
                showToast("Cloud flaked. Crew is local for now.")
            }
        }
    }

    private func insertLocalCrew(name: String, code: String) {
        let crew = Crew(name: name, inviteCode: code)
        modelContext.insert(crew)
        try? modelContext.save()
        Haptics.success()
    }

    /// The one true code alphabet — no ambiguous glyphs (0/O, 1/I/L).
    /// The join sheet filters input against this exact set, so the two
    /// can never drift apart.
    static let inviteAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    /// 6 characters drawn from `inviteAlphabet`.
    static func makeInviteCode() -> String {
        let alphabet = Array(inviteAlphabet)
        return String((0..<6).map { _ in alphabet.randomElement() ?? "B" })
    }
}

// MARK: - Refresh key

private struct LBRefreshKey: Equatable {
    let weekStart: Date
    let myCount: Int
    let myLastCount: Int
    let crewID: UUID?
}

// MARK: - Podium slot

private struct LBPodiumSlot: Identifiable {
    let entry: LeaderboardEntry
    let rank: Int
    var id: UUID { entry.id }
}

// MARK: - Colors

private enum LBColor {
    static let gold = Color(hex: "#FFD34D")
    static let silver = Theme.silver
    static let bronze = Color(hex: "#D08B4C")
    static let deltaUp = Color(hex: "#C9E265")          // green-ish yellow
    static let deltaDown = Theme.bullRed.opacity(0.55)  // dimmed red
}

// MARK: - Podium column

private struct LBPodiumColumn: View {
    let entry: LeaderboardEntry
    let rank: Int
    let isReigningChampion: Bool
    let namespace: Namespace.ID
    let reduceMotion: Bool

    @State private var crownFloats = false

    private var medal: Color {
        switch rank {
        case 1: LBColor.gold
        case 2: LBColor.silver
        default: LBColor.bronze
        }
    }

    private var pedestalHeight: CGFloat {
        switch rank {
        case 1: 116
        case 2: 84
        default: 62
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Last week's champion wears the crown all week — even from silver.
            if isReigningChampion {
                Text("👑")
                    .font(.system(size: 26))
                    .offset(y: crownFloats ? -4 : 3)
                    .accessibilityHidden(true)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            crownFloats = true
                        }
                    }
            }
            LBInitialsAvatar(name: entry.name, size: rank == 1 ? 56 : 46, ring: medal)
            Text(entry.name)
                .font(Theme.label(12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(entry.weeklyCount)")
                .font(Theme.heroFont(rank == 1 ? 34 : 26))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .accessibilityLabel(
                    "\(entry.name), \(entry.weeklyCount) cans this week"
                        + (isReigningChampion ? ", reigning champion" : "")
                )
            Color.clear
                .frame(height: pedestalHeight)
                .glassEffect(.regular.tint(medal.opacity(0.35)), in: .rect(cornerRadius: 18))
                .glassEffectID(entry.id, in: namespace)
                .overlay(alignment: .top) {
                    Text("\(rank)")
                        .font(Theme.heroFont(24))
                        .foregroundStyle(medal)
                        .padding(.top, 10)
                        .accessibilityHidden(true)
                }
                .shadow(
                    color: medal.opacity(rank == 1 ? 0.45 : 0.22),
                    radius: rank == 1 ? 22 : 10,
                    y: 6
                )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ranked row

private struct LBRankRow: View {
    let entry: LeaderboardEntry
    let rank: Int
    var isReigningChampion: Bool = false

    private var rankColor: Color {
        switch rank {
        case 1: LBColor.gold
        case 2: LBColor.silver
        case 3: LBColor.bronze
        default: .white.opacity(0.35)
        }
    }

    var body: some View {
        GlassCard(radius: 22, tint: entry.isYou ? Theme.energyYellow : nil) {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(Theme.label(15))
                    .foregroundStyle(rankColor)
                    .frame(width: 26)
                LBInitialsAvatar(
                    name: entry.name,
                    size: 42,
                    ring: entry.isYou ? Theme.energyYellow : .white.opacity(0.18)
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(Theme.label(15))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        // Fell off the podium; kept the crown. Rules are rules.
                        if isReigningChampion {
                            Text("👑")
                                .font(.system(size: 13))
                                .accessibilityLabel("Reigning champion")
                        }
                    }
                    if entry.isYou {
                        MicroLabel(text: "THAT'S YOU")
                    }
                }
                Spacer(minLength: 8)
                LBDeltaBadge(delta: entry.lastWeekDelta)
                Text("\(entry.weeklyCount)")
                    .font(Theme.heroFont(30))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(entry.weeklyCount) cans this week")
            }
        }
    }
}

// MARK: - Delta badge

private struct LBDeltaBadge: View {
    let delta: Int

    var body: some View {
        Group {
            if delta > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                    Text("\(delta)")
                }
                .foregroundStyle(LBColor.deltaUp)
            } else if delta < 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                    Text("\(-delta)")
                }
                .foregroundStyle(LBColor.deltaDown)
            } else {
                Image(systemName: "minus")
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .font(Theme.label(11))
        .accessibilityLabel(label)
    }

    private var label: String {
        if delta > 0 {
            "Up \(delta) from last week"
        } else if delta < 0 {
            "Down \(-delta) from last week"
        } else {
            "Same as last week"
        }
    }
}

// MARK: - Initials avatar

private struct LBInitialsAvatar: View {
    let name: String
    var size: CGFloat = 40
    var ring: Color = .white.opacity(0.2)

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(Theme.racingBlueDark.opacity(0.6))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(ring, lineWidth: 2)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Friend detail sheet

private struct LBFlavorRow: Identifiable {
    let flavor: String
    let count: Int
    var id: String { flavor }
}

private struct LBFriendDetailSheet: View {
    let entry: LeaderboardEntry

    @Query private var skus: [SKU]

    private var rows: [LBFlavorRow] {
        entry.flavorSummary
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { LBFlavorRow(flavor: $0.key, count: $0.value) }
    }

    private func accent(for flavor: String) -> Color {
        skus.first { $0.flavor.caseInsensitiveCompare(flavor) == .orderedSame }?.accent ?? Theme.silver
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    LBInitialsAvatar(name: entry.name, size: 52, ring: Theme.racingBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(Theme.heroFont(26))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        HStack(spacing: 8) {
                            Text("\(entry.weeklyCount) cans this week")
                                .font(Theme.label(13))
                                .foregroundStyle(.white.opacity(0.6))
                            LBDeltaBadge(delta: entry.lastWeekDelta)
                        }
                    }
                    Spacer()
                }
                MicroLabel(text: "FLAVOR BREAKDOWN")
                if rows.isEmpty {
                    Text("No flavor intel. Impressively secretive.")
                        .font(Theme.label(13))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    let maxCount = max(rows.first?.count ?? 1, 1)
                    VStack(spacing: 12) {
                        ForEach(rows) { row in
                            HStack(spacing: 12) {
                                Text(row.flavor)
                                    .font(Theme.label(13))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(width: 110, alignment: .leading)
                                    .lineLimit(1)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(.white.opacity(0.08))
                                        Capsule()
                                            .fill(accent(for: row.flavor))
                                            .frame(width: max(10, geo.size.width * CGFloat(row.count) / CGFloat(maxCount)))
                                    }
                                }
                                .frame(height: 10)
                                Text("\(row.count)")
                                    .font(Theme.label(13))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .frame(width: 26, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(row.flavor), \(row.count) cans")
                        }
                    }
                }
                Spacer()
            }
            .padding(24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }
}

// MARK: - Join sheet

private struct LBJoinCrewSheet: View {
    /// Surfaces a one-line toast on the leaderboard after the sheet closes
    /// (used when the cloud join flakes and we fall back to a local crew).
    var onToast: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var code = ""
    @State private var joining = false

    /// Only glyphs a real code can contain — same set `makeInviteCode` mints.
    private static let allowedGlyphs = Set(LeaderboardView.inviteAlphabet)

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                MicroLabel(text: "GOT A CODE?")
                Text("Six characters between you and rivalry.")
                    .font(Theme.label(14))
                    .foregroundStyle(.white.opacity(0.6))
                TextField("ABC123", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .onChange(of: code) { _, newValue in
                        // Uppercase as you type; drop anything makeInviteCode
                        // would never generate (0/O, 1/I/L, non-ASCII, emoji).
                        code = String(
                            newValue.uppercased()
                                .filter { Self.allowedGlyphs.contains($0) }
                                .prefix(6)
                        )
                    }
                    .accessibilityLabel("Invite code")
                Button {
                    join()
                } label: {
                    Text("JOIN CREW")
                        .font(Theme.label(15))
                        .kerning(1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)
                .foregroundStyle(.black)
                .disabled(code.count != 6 || joining)
            }
            .padding(28)
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    /// Signed in against a live Supabase project → the code resolves
    /// server-side and comes back with the crew's real name + serverID.
    /// Anything else — placeholder config, signed out, or the cloud flaking —
    /// lands on exactly the classic local-only join.
    private func join() {
        let entered = code
        guard SupabaseConfig.isConfigured, SupabaseAuth.shared.isSignedIn else {
            joinLocally(code: entered)
            dismiss()
            return
        }
        joining = true
        Task {
            do {
                let joined = try await CloudLeaderboardService().joinCrew(code: entered)
                let crew = Crew(name: joined.name, inviteCode: entered)
                crew.serverID = joined.serverID
                modelContext.insert(crew)
                try? modelContext.save()
                Haptics.success()
            } catch {
                joinLocally(code: entered)
                onToast("Cloud flaked. Crew is local for now.")
            }
            joining = false
            dismiss()
        }
    }

    private func joinLocally(code: String) {
        let crew = Crew(name: "THE PIT CREW", inviteCode: code)
        modelContext.insert(crew)
        try? modelContext.save()
        Haptics.success()
    }
}
