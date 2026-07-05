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
    @State private var celebrationCenter = CelebrationCenter.shared
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
            // Clearance so the floating scan button never sits on the last
            // row of any tab's scroll content when scrolled to the end.
            .contentMargins(.bottom, 140, for: .scrollContent)
        }
        .overlay(alignment: .bottom) {
            scanButton
                .padding(.bottom, 76) // float clear of the glass tab bar
        }
        .overlay {
            // Manual-log path: the Can Drop celebration plays here at the
            // root, over every tab, once the sheet has dismissed itself.
            if let pending = celebrationCenter.pending {
                CelebrationView(
                    sku: pending.sku,
                    result: pending.result,
                    weekCount: pending.weekCount,
                    todayCount: pending.todayCount,
                    streak: pending.streak
                ) {
                    celebrationCenter.pending = nil
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            ScannerSheet()
                .navigationTransition(.zoom(sourceID: "scanButton", in: glassNamespace))
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.impact(weight: .heavy), trigger: scanTapCount)
        .preferredColorScheme(.dark)
        #if DEBUG
        // `-celebrationDemo` launch arg: auto-play the Can Drop celebration
        // 2s after launch so the full animation can be recorded headlessly.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-celebrationDemo") else { return }
            try? await Task.sleep(for: .seconds(2))
            let context = modelContext
            let skus = (try? context.fetch(FetchDescriptor<SKU>())) ?? []
            guard let sku = skus.first(where: { $0.canStyle == "acai" || $0.flavor.localizedCaseInsensitiveContains("açaí") }) ?? skus.first else { return }
            let result = LogPipeline.log(sku: sku, source: .manual, context: context)
            let logs = (try? context.fetch(FetchDescriptor<CanLog>())) ?? []
            celebrationCenter.celebrate(
                sku: sku,
                result: result,
                weekCount: StatsEngine.weekCount(logs, weekOf: .now),
                todayCount: StatsEngine.todayCount(logs),
                streak: StatsEngine.currentStreak(logs)
            )
        }
        #endif
    }

    @Environment(\.modelContext) private var modelContext

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
            // Real morph: the scanner cover zooms out of this button and
            // melts back into it on dismiss. (glassEffectID can't morph
            // across presentation contexts — this can.)
            .matchedTransitionSource(id: "scanButton", in: glassNamespace)
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
