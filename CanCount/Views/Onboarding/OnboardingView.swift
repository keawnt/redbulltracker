import SwiftUI
import SwiftData
import UserNotifications

// MARK: - OnboardingView

/// First-launch flow, in the house style: dark canvas, one hero per screen,
/// massive rounded type, dry copy, glass buttons.
///
/// Pages: value pitch (can) → the numbers → the crew → callsign + primers.
///
/// SIGN IN WITH APPLE SLOT: when the backend lands (Supabase or CloudKit),
/// the "START COUNTING" button on the last page becomes SignInWithAppleButton
/// (AuthenticationServices) with a "count solo for now" escape hatch below it
/// — the app never requires an account to log cans (handoff non-negotiable).
struct OnboardingView: View {
    /// Flipped when the user finishes; the app root swaps to RootTabView.
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = 0
    @State private var displayName = ""
    @State private var wantsNudges = false
    @FocusState private var nameFocused: Bool

    private let pageCount = 4

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            TabView(selection: $page) {
                pitchPage.tag(0)
                numbersPage.tag(1)
                crewPage.tag(2)
                callsignPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.keyboard, edges: .bottom)

            VStack {
                Spacer()
                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.spring, value: page)
    }

    // MARK: Pages

    private var pitchPage: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)
            CanArtwork(sku: nil, height: 300)
            VStack(spacing: 12) {
                MicroLabel(text: "CanCount")
                Text("Count every can.")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Scan it. Log it. Own the number.\nFlight-tracker energy, energy-drink subject matter.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer(minLength: 140)
        }
    }

    private var numbersPage: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 60)
            VStack(spacing: 4) {
                Text("14")
                    .font(Theme.heroFont(140))
                    .foregroundStyle(.white)
                    .shadow(color: Theme.energyYellow.opacity(0.25), radius: 30)
                MicroLabel(text: "Cans this week")
            }
            HStack(spacing: 12) {
                StatPill(title: "Today", value: "3", systemImage: "cylinder.fill")
                StatPill(title: "Caffeine", value: "342mg", accent: Theme.racingBlue, systemImage: "bolt.fill")
                StatPill(title: "Streak", value: "12", accent: Theme.bullRed, systemImage: "flame.fill")
            }
            .padding(.horizontal, 24)
            Text("Weekly totals, caffeine math, streaks,\nand a recap card worth bragging with.")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
            Spacer(minLength: 140)
        }
    }

    private var crewPage: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 60)
            Text("🏆")
                .font(.system(size: 88))
                .padding(28)
                .glassEffect(.regular.tint(Theme.energyYellow.opacity(0.2)), in: .circle)
            VStack(spacing: 12) {
                Text("Beat your crew.")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Weekly leaderboards. A crown on the champion.\nLindsay is two cans behind you.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer(minLength: 140)
        }
    }

    private var callsignPage: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 60)
            VStack(spacing: 10) {
                MicroLabel(text: "Last thing")
                Text("What do we call you?")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            TextField("Your name", text: $displayName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tint(Theme.energyYellow)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 48)
                .accessibilityLabel("Display name")

            Toggle(isOn: $wantsNudges) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nudge me near stores")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Store Radar asks if a Red Bull happened. Off by default, zero judgment.")
                        .font(Theme.label(11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .tint(Theme.energyYellow)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .padding(.horizontal, 32)

            Spacer(minLength: 160)
        }
        .onTapGesture { nameFocused = false }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 16) {
            // Page dots
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.energyYellow : .white.opacity(0.2))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            .accessibilityHidden(true)

            if page < pageCount - 1 {
                Button {
                    Haptics.tick()
                    page += 1
                } label: {
                    Text("CONTINUE")
                        .font(Theme.label(15))
                        .kerning(2.5)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)
                .accessibilityLabel("Continue")

                Button {
                    Haptics.tick()
                    page = pageCount - 1
                } label: {
                    Text("Skip the tour")
                        .font(Theme.label(12))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    finish()
                } label: {
                    Text("START COUNTING")
                        .font(Theme.label(15))
                        .kerning(2.5)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)
                .accessibilityLabel("Start counting")
                // ^ SIWA SLOT: replace with SignInWithAppleButton + a
                //   "count solo for now" plain button when the backend lands.
            }
        }
    }

    private func finish() {
        Haptics.success()
        let profile = UserProfile.current(in: modelContext)
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            profile.displayName = trimmed
        }
        try? modelContext.save()

        if wantsNudges {
            StoreRadarService.shared.isEnabled = true
        }
        onFinished()
    }
}
