import SwiftUI
import UIKit

// MARK: - FindFriendsSheet

/// Contact matching, the privacy-forward way: numbers are hashed on-device
/// and only the hashes travel — ContactsMatcher does all the work, this
/// sheet just renders its state machine.
///
/// Only ever presented when SupabaseConfig.isConfigured and the user is
/// signed in (LeaderboardView gates the affordance), so there's no
/// placeholder-config path to worry about here.
struct FindFriendsSheet: View {
    @Environment(\.openURL) private var openURL

    @State private var phone = ""
    @State private var publishedNumber = false
    @State private var publishFailed = false

    private var matcher: ContactsMatcher { .shared }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MicroLabel(text: "FIND FRIENDS")
                    switch matcher.state {
                    case .idle, .needsPermission:
                        intro
                    case .denied:
                        denied
                    case .searching:
                        searching
                    case .done:
                        results
                    case .failed(let message):
                        failed(message)
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your people are already here.")
                .font(Theme.heroFont(28))
                .foregroundStyle(.white)
            Text("We hash numbers on your phone. Nobody sees your contacts.")
                .font(Theme.label(13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tick()
                Task { await ContactsMatcher.shared.findFriends() }
            } label: {
                Text("FIND MY PEOPLE")
                    .font(Theme.label(15))
                    .kerning(1.5)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.energyYellow)

            publishField
                .padding(.top, 8)
        }
    }

    // MARK: Let friends find you

    /// Optional reverse lane: publish your own (hashed) number so friends
    /// running the same search can find you.
    private var publishField: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroLabel(text: "LET FRIENDS FIND YOU")
            Text("Optional. Your number is hashed before it leaves the phone.")
                .font(Theme.label(11))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("Phone number", text: $phone)
                    .keyboardType(.phonePad)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(Theme.energyYellow)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityLabel("Your phone number")
                    .onChange(of: phone) { _, _ in
                        publishedNumber = false
                        publishFailed = false
                    }
                Button {
                    publish()
                } label: {
                    Image(systemName: publishedNumber ? "checkmark" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.glass)
                .disabled(phone.trimmingCharacters(in: .whitespaces).count < 7 || publishedNumber)
                .accessibilityLabel(publishedNumber ? "Number published" : "Publish my number")
            }
            if publishFailed {
                Text("Didn't take. Try again in a bit.")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.bullRed.opacity(0.8))
            }
        }
    }

    private func publish() {
        Haptics.tick()
        publishFailed = false
        let raw = phone
        Task {
            do {
                try await ContactsMatcher.shared.publishMyNumber(raw)
                publishedNumber = true
                Haptics.success()
            } catch {
                publishFailed = true
            }
        }
    }

    // MARK: Denied

    private var denied: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Contacts are off.")
                .font(Theme.heroFont(28))
                .foregroundStyle(.white)
            Text("Flip the switch in Settings and we'll take it from there.")
                .font(Theme.label(13))
                .foregroundStyle(.white.opacity(0.55))
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("OPEN SETTINGS")
                    .font(Theme.label(15))
                    .kerning(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: Searching

    private var searching: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Theme.energyYellow)
            Text("Hashing numbers. Naming no names.")
                .font(Theme.label(13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        if matcher.matches.isEmpty {
            VStack(spacing: 14) {
                Text("📇")
                    .font(.system(size: 44))
                    .accessibilityHidden(true)
                Text("Nobody yet. Be the first domino.")
                    .font(Theme.heroFont(22))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                publishField
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                MicroLabel(text: "\(matcher.matches.count) found")
                ForEach(matcher.matches) { friend in
                    FFMatchRow(friend: friend)
                }
                // Joining by crew ID isn't a thing (codes are the only door),
                // so crewed friends come with homework instead of a button.
                Text("See a crew you like? Ask them for the code.")
                    .font(Theme.label(12))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Failed

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("That didn't work.")
                .font(Theme.heroFont(26))
                .foregroundStyle(.white)
            Text(message)
                .font(Theme.label(13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tick()
                Task { await ContactsMatcher.shared.findFriends() }
            } label: {
                Text("TRY AGAIN")
                    .font(Theme.label(15))
                    .kerning(1.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
    }
}

// MARK: - Match row

private struct FFMatchRow: View {
    let friend: ContactsMatcher.MatchedFriend

    var body: some View {
        GlassCard(radius: 22) {
            HStack(spacing: 14) {
                FFInitialsAvatar(name: friend.displayName)
                VStack(alignment: .leading, spacing: 3) {
                    Text(friend.displayName)
                        .font(Theme.label(15))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let crewName = friend.crewName {
                        Text("In crew \(crewName)")
                            .font(Theme.label(11))
                            .foregroundStyle(Theme.energyYellow.opacity(0.85))
                            .lineLimit(1)
                    } else {
                        Text("No crew yet. Recruit them.")
                            .font(Theme.label(11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Initials avatar

/// Same squircle avatar language as the leaderboard rows.
private struct FFInitialsAvatar: View {
    let name: String
    var size: CGFloat = 42

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
                    .strokeBorder(.white.opacity(0.18), lineWidth: 2)
            }
            .accessibilityHidden(true)
    }
}
