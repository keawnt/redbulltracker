import SwiftUI
import SwiftData

/// Manual logging for when the can is already in the recycling.
/// Stage 1: grid of flavor tiles. Stage 2: size selector + LOG IT.
struct ManualLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SKU.flavor) private var skus: [SKU]

    /// Representative SKU of the chosen flavor (nil = still on the grid).
    @State private var pickedFlavor: SKU?
    @State private var selectedSKU: SKU?
    @State private var didLog = false
    @State private var celebrationLine: String?
    @State private var confettiTrigger = 0
    @State private var tilesAppeared = false

    init() {}

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
            ConfettiBurst(trigger: confettiTrigger)
                .ignoresSafeArea()
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            header
            if skus.isEmpty {
                emptyState
            } else if let picked = pickedFlavor {
                sizeStage(for: picked)
                    .transition(stageTransition(forward: true))
            } else {
                flavorGrid
                    .transition(stageTransition(forward: false))
            }
        }
        .animation(motionAnimation, value: pickedFlavor)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            MicroLabel(text: "THE HONOR SYSTEM")
            Text(pickedFlavor == nil ? "Can already recycled? We believe you." : "Pick your size. Be honest.")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    // MARK: Stage 1 — flavor grid

    private var flavorGrid: some View {
        let representatives = ScanCatalog.flavorRepresentatives(from: skus)
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(Array(representatives.enumerated()), id: \.element.persistentModelID) { index, sku in
                    ScanFlavorTile(sku: sku, compact: false) {
                        Haptics.tick()
                        pickedFlavor = sku
                        selectedSKU = sku
                    }
                    .opacity(tilesAppeared ? 1 : 0)
                    .offset(y: tilesAppeared ? 0 : 14)
                    .animation(
                        reduceMotion ? nil : Theme.spring.delay(Double(index) * 0.035),
                        value: tilesAppeared
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if reduceMotion {
                tilesAppeared = true
            } else {
                withAnimation { tilesAppeared = true }
            }
        }
    }

    // MARK: Stage 2 — size + confirm

    private func sizeStage(for picked: SKU) -> some View {
        let display = selectedSKU ?? picked
        let options = skus
            .filter { $0.flavor == picked.flavor }
            .sorted { $0.sizeML < $1.sizeML }

        return VStack(spacing: 20) {
            HStack {
                Button {
                    Haptics.tick()
                    pickedFlavor = nil
                    selectedSKU = nil
                } label: {
                    Label("All flavors", systemImage: "chevron.left")
                        .font(Theme.label(12))
                }
                .buttonStyle(.glass)
                Spacer()
                CanChip(sku: display)
            }
            .padding(.horizontal, 20)

            CanArtwork(sku: display, height: 190, floating: true)

            VStack(spacing: 4) {
                Text(display.name)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("\(display.caffeineMG)mg caffeine · \(sugarLabel(for: display)) sugar · \(display.calories) cal")
                    .font(Theme.label(12))
                    .foregroundStyle(.white.opacity(0.55))
                    .accessibilityLabel("\(display.caffeineMG) milligrams caffeine, \(sugarLabel(for: display)) sugar, \(display.calories) calories")
            }
            .padding(.horizontal, 24)
            .animation(motionAnimation, value: selectedSKU)

            if options.count > 1 {
                ScanSizeSelector(options: options, selection: sizeBinding)
                    .padding(.horizontal, 24)
            }

            if didLog {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.energyYellow)
                        .accessibilityHidden(true)
                    Text(celebrationLine ?? "Logged. Honor intact.")
                        .font(Theme.label(13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.vertical, 8)
            } else {
                Button {
                    logIt(display)
                } label: {
                    Text("LOG IT")
                        .font(Theme.label(16))
                        .kerning(3)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "refrigerator")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(Theme.energyYellow)
                .accessibilityHidden(true)
            Text("The flavor list is empty.")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Seed data hasn't landed yet. Restart the app and the fridge restocks itself.")
                .font(Theme.label(13))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxHeight: .infinity)
    }

    // MARK: Helpers

    private var sizeBinding: Binding<SKU?> {
        Binding(
            get: { selectedSKU },
            set: { newValue in
                guard let newValue else { return }
                Haptics.tick()
                selectedSKU = newValue
            }
        )
    }

    private func sugarLabel(for sku: SKU) -> String {
        if sku.sugarFree { return "0g" }
        return sku.sugarG.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(sku.sugarG))g"
            : String(format: "%.1fg", sku.sugarG)
    }

    private var motionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : Theme.spring
    }

    private func stageTransition(forward: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let edge: Edge = forward ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge).combined(with: .opacity)
        )
    }

    private func logIt(_ sku: SKU) {
        guard !didLog else { return }
        let result = LogPipeline.log(sku: sku, source: .manual, context: modelContext)

        guard result.persisted else {
            Haptics.warning()
            celebrationLine = "That one didn't save. Try again."
            return
        }

        Haptics.success()
        didLog = true

        // The Can Drop celebration plays at the root, over everything, the
        // moment this sheet is out of the way.
        let allLogs = (try? modelContext.fetch(FetchDescriptor<CanLog>())) ?? []
        CelebrationCenter.shared.celebrate(
            sku: sku,
            result: result,
            weekCount: StatsEngine.weekCount(allLogs, weekOf: .now),
            todayCount: StatsEngine.todayCount(allLogs),
            streak: StatsEngine.currentStreak(allLogs)
        )
        dismiss()
    }
}
