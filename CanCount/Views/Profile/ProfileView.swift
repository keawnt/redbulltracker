import SwiftUI
import SwiftData

/// Profile tab — the operator's card.
/// Squircle avatar, editable callsign, the badge wall, and the very few
/// settings this app deigns to have.
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \CanLog.timestamp, order: .reverse) private var logs: [CanLog]

    @State private var profile: UserProfile?
    @State private var selectedBadge: Badge?
    @FocusState private var nameFieldFocused: Bool

    init() {}

    /// Streak derived live from the logs — the stored `profile.streakCount`
    /// only updates when you log, so it happily overstates a dead streak.
    /// The logs never lie.
    private var dayStreak: Int {
        StatsEngine.currentStreak(logs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let profile {
                    header(for: profile)
                    statTrio(for: profile)
                    LineupLoyaltySection(logs: logs)
                    badgeWall(for: profile)
                    StoreRadarSection()
                    settings(for: profile)
                }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 120) // clear the floating scan button
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.canvas.ignoresSafeArea())
        .task {
            if profile == nil {
                profile = UserProfile.current(in: modelContext)
            }
        }
    }

    // MARK: - Header

    private func header(for profile: UserProfile) -> some View {
        @Bindable var profile = profile
        return VStack(alignment: .leading, spacing: 20) {
            MicroLabel(text: "Profile")

            HStack(spacing: 16) {
                avatar(for: profile.displayName)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("You", text: $profile.displayName)
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .tint(Theme.energyYellow)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFieldFocused)
                            .onSubmit { commitName(profile) }
                            .accessibilityLabel("Display name. Tap to edit.")

                        if !nameFieldFocused {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                                .accessibilityHidden(true)
                        }
                    }

                    HStack(spacing: 10) {
                        MicroLabel(text: "Joined \(profile.joinDate.formatted(.dateTime.month(.wide).year()))")
                        if dayStreak > 0 {
                            Text("🔥 \(dayStreak)")
                                .font(Theme.label(11))
                                .foregroundStyle(Theme.energyYellow)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.06), in: .capsule)
                                .accessibilityLabel("\(dayStreak) day streak")
                        }
                    }
                }
            }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            if !focused { commitName(profile) }
        }
    }

    private func avatar(for name: String) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.racingBlue, Theme.racingBlueDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 84, height: 84)
            .overlay {
                Text(initials(from: name))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: Theme.racingBlue.opacity(0.35), radius: 14, y: 6)
            .accessibilityHidden(true)
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    private func commitName(_ profile: UserProfile) {
        let trimmed = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.displayName = trimmed.isEmpty ? "You" : trimmed
        try? modelContext.save()
    }

    // MARK: - Stat trio

    private func statTrio(for profile: UserProfile) -> some View {
        let earned = earnedCount(for: profile)
        let total = Badge.allCases.count
        return HStack(spacing: 12) {
            StatPill(title: "Total cans", value: "\(logs.count)", accent: Theme.energyYellow, systemImage: "cylinder.fill")
                .accessibilityLabel("\(logs.count) total cans logged")
            StatPill(title: "Day streak", value: "\(dayStreak)", accent: Theme.bullRed, systemImage: "flame.fill")
                .accessibilityLabel("\(dayStreak) day streak")
            StatPill(title: "Badges", value: "\(earned)/\(total)", accent: Theme.racingBlue, systemImage: "medal.fill")
                .accessibilityLabel("\(earned) of \(total) badges earned")
        }
    }

    private func earnedCount(for profile: UserProfile) -> Int {
        Badge.allCases.filter { profile.badges.contains($0.rawValue) }.count
    }

    // MARK: - Badge wall

    private func badgeWall(for profile: UserProfile) -> some View {
        let earnedSet = Set(profile.badges)
        let earned = earnedCount(for: profile)
        return VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Badge wall")

            if earned == 0 {
                Text("All locked. The wall remembers who shows up.")
                    .font(Theme.label(12))
                    .foregroundStyle(.white.opacity(0.4))
            }

            GlassEffectContainer {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    ForEach(Badge.allCases) { badge in
                        BadgeTile(
                            badge: badge,
                            earned: earnedSet.contains(badge.rawValue),
                            isSelected: selectedBadge == badge
                        )
                        .onTapGesture {
                            Haptics.tick()
                            withAnimation(reduceMotion ? nil : Theme.spring) {
                                selectedBadge = (selectedBadge == badge) ? nil : badge
                            }
                        }
                    }
                }
            }

            if let selectedBadge {
                badgeDetail(selectedBadge, earned: earnedSet.contains(selectedBadge.rawValue))
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
            }
        }
    }

    private func badgeDetail(_ badge: Badge, earned: Bool) -> some View {
        GlassCard(tint: earned ? Theme.energyYellow : nil) {
            HStack(spacing: 14) {
                Image(systemName: earned ? badge.icon : "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(earned ? Theme.energyYellow : .white.opacity(0.45))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(badge.title)
                        .font(Theme.label(14))
                        .foregroundStyle(.white)
                    Text(badge.detail)
                        .font(Theme.label(12))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Settings

    private func settings(for profile: UserProfile) -> some View {
        @Bindable var profile = profile
        return VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Settings")

            GlassCard {
                VStack(spacing: 18) {
                    // Caffeine ceiling
                    HStack(spacing: 14) {
                        settingIcon("bolt.heart.fill", tint: Theme.bullRed)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Caffeine ceiling")
                                .font(Theme.label(14))
                                .foregroundStyle(.white)
                            Text("One gentle nudge per day. Never a lecture.")
                                .font(Theme.label(11))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("\(profile.caffeineWarningMG)mg")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.energyYellow)
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : Theme.spring, value: profile.caffeineWarningMG)
                                .accessibilityLabel("Warning threshold \(profile.caffeineWarningMG) milligrams")
                            Stepper(
                                "Caffeine warning threshold",
                                value: $profile.caffeineWarningMG,
                                in: 100...800,
                                step: 50
                            )
                            .labelsHidden()
                        }
                    }

                    settingsDivider

                    // Notifications
                    HStack(spacing: 14) {
                        settingIcon("bell.badge.fill", tint: Theme.energyYellow)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Notifications")
                                .font(Theme.label(14))
                                .foregroundStyle(.white)
                            Text("Reminders to log. Never at 3am. Probably.")
                                .font(Theme.label(11))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Toggle("Notifications", isOn: $profile.notificationsEnabled)
                            .labelsHidden()
                            .tint(Theme.energyYellow)
                    }

                    settingsDivider

                    // iCloud sync status.
                    // CloudKit swap point: when the Leaderboard goes live, replace this
                    // static row with real CKSyncEngine / CloudKit account status and
                    // flip CanLog.synced as records land in the private database.
                    HStack(spacing: 14) {
                        settingIcon("icloud.slash.fill", tint: Theme.silver)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("iCloud sync")
                                .font(Theme.label(14))
                                .foregroundStyle(.white)
                            Text("Local only for now. Your numbers stay between us.")
                                .font(Theme.label(11))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text("LOCAL")
                            .font(Theme.label(10))
                            .kerning(1.5)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.white.opacity(0.06), in: .capsule)
                    }
                    .accessibilityElement(children: .combine)
                }
                .padding(16)
            }
            .onChange(of: profile.caffeineWarningMG) {
                Haptics.tick()
                try? modelContext.save()
            }
            .onChange(of: profile.notificationsEnabled) {
                Haptics.tick()
                try? modelContext.save()
            }
        }
    }

    private var settingsDivider: some View {
        Divider().overlay(.white.opacity(0.08))
    }

    private func settingIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Text("CANCOUNT")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .kerning(4)
                .foregroundStyle(.white.opacity(0.35))
            Text(versionString)
                .font(Theme.label(11))
                .foregroundStyle(.white.opacity(0.25))
            Text("Fueled by the subject matter.")
                .font(Theme.label(11))
                .foregroundStyle(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }
}

// MARK: - Badge tile

/// One glass tile on the badge wall. Earned tiles glow energy yellow;
/// locked tiles sit frosted and dimmed behind a small padlock.
private struct BadgeTile: View {
    let badge: Badge
    let earned: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: badge.icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(earned ? Theme.energyYellow : Theme.silver)
                .frame(height: 44)
            Text(badge.title.uppercased())
                .font(Theme.label(10))
                .kerning(1.5)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(earned ? 0.85 : 0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 10)
        .glassEffect(
            earned ? .regular.tint(Theme.energyYellow.opacity(0.25)) : .regular,
            in: .rect(cornerRadius: 22)
        )
        .opacity(earned ? 1 : 0.35)
        .overlay(alignment: .topTrailing) {
            if !earned {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(10)
            }
        }
        .shadow(color: earned ? Theme.energyYellow.opacity(0.35) : .clear, radius: earned ? 14 : 0, y: 4)
        .scaleEffect(isSelected ? 1.04 : 1)
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(badge.title). \(earned ? "Earned" : "Locked")")
        .accessibilityHint(badge.detail)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [SKU.self, CanLog.self, UserProfile.self, Crew.self], inMemory: true)
        .preferredColorScheme(.dark)
}
