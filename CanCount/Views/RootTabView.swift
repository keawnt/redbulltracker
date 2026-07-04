import SwiftUI
import SwiftData

// MARK: - AppTab

enum AppTab: String, Hashable, CaseIterable {
    case home, stats, leaderboard, profile
}

// MARK: - RootTabView

/// The app's root chrome: four glass tabs on the dark canvas plus the floating
/// yellow scan button that morphs into the scanner.
struct RootTabView: View {
    @State private var selection: AppTab = .home
    @State private var isScannerPresented = false
    @State private var scanTapCount = 0
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        ZStack {
            // Never a light background — the canvas is the floor of everything.
            Theme.canvas.ignoresSafeArea()

            TabView(selection: $selection) {
                Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                    HomeView()
                }
                Tab("Stats", systemImage: "chart.bar.fill", value: AppTab.stats) {
                    StatsView()
                }
                Tab("Crew", systemImage: "trophy.fill", value: AppTab.leaderboard) {
                    LeaderboardView()
                }
                Tab("Profile", systemImage: "person.fill", value: AppTab.profile) {
                    ProfileView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
        }
        .overlay(alignment: .bottom) {
            scanButton
                .padding(.bottom, 76) // float clear of the glass tab bar
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            ScannerSheet()
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.impact(weight: .heavy), trigger: scanTapCount)
        .preferredColorScheme(.dark)
    }

    // MARK: Scan button

    /// 68pt prominent yellow glass circle. Lives in a GlassEffectContainer with a
    /// glassEffectID so the glass morphs as the scanner presentation swallows it —
    /// the button melts away on open and re-forms on dismiss.
    private var scanButton: some View {
        GlassEffectContainer {
            Button {
                scanTapCount += 1
                if reduceMotion {
                    // Reduce Motion: plain state change, the cover's own transition
                    // handles the rest without the springy morph.
                    isScannerPresented = true
                } else {
                    withAnimation(Theme.spring) {
                        isScannerPresented = true
                    }
                }
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 68, height: 68)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Theme.energyYellow.opacity(0.85)).interactive())
            .glassEffectID("scanButton", in: glassNamespace)
        }
        .shadow(color: Theme.energyYellow.opacity(0.35), radius: 18, y: 6)
        // Morph-away while the scanner is up; spring back when it dismisses.
        .scaleEffect(isScannerPresented && !reduceMotion ? 0.4 : 1)
        .opacity(isScannerPresented ? 0 : 1)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Theme.spring, value: isScannerPresented)
        .accessibilityLabel("Scan a can")
        .accessibilityHint("Opens the barcode scanner")
    }
}

#Preview {
    RootTabView()
        .modelContainer(
            try! ModelContainer(
                for: SKU.self, CanLog.self, UserProfile.self, Crew.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        )
}
