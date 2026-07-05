import SwiftUI
import SwiftData
import AVFoundation
import VisionKit
import UIKit

// MARK: - Scan state machine

/// .scanning -> .resolving(code) -> .found(SKU) / .rejected(name) / .unavailable(code)
/// -> confirm -> celebration -> dismiss
enum ScanPhase: Equatable {
    case scanning
    case resolving(String)
    case found(SKU)
    case rejected(String?)
    /// The lookup itself failed (offline, timeout, API hiccup) — never blame the can.
    case unavailable(String)
}

/// Shared catalog helpers for the scan + manual-log flows.
enum ScanCatalog {
    /// One representative SKU per distinct flavor (the smallest size), sorted by flavor name.
    static func flavorRepresentatives(from skus: [SKU]) -> [SKU] {
        var seen = Set<String>()
        return skus
            .sorted { $0.sizeML < $1.sizeML }
            .filter { seen.insert($0.flavor).inserted }
            .sorted { $0.flavor.localizedCaseInsensitiveCompare($1.flavor) == .orderedAscending }
    }

    /// Barcode match with normalization: raw code, 13-digit code with the leading
    /// zero stripped, and 12-digit code with a leading zero added (UPC-A <-> EAN-13).
    static func matchSKU(code rawCode: String, in skus: [SKU]) -> SKU? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [code]
        if code.count == 13, code.hasPrefix("0") {
            candidates.append(String(code.dropFirst()))
        }
        if code.count == 12 {
            candidates.append("0" + code)
        }
        for candidate in candidates {
            if let match = skus.first(where: { $0.barcode == candidate }) {
                return match
            }
        }
        return nil
    }
}

// MARK: - ScannerSheet

struct ScannerSheet: View {
    private enum ScanCameraAuthState {
        case undetermined, authorized, denied
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \SKU.name) private var skus: [SKU]

    @State private var phase: ScanPhase = .scanning
    @State private var selectedSKU: SKU?
    @State private var didLog = false
    @State private var saveErrorLine: String?
    @State private var showManualLog = false
    @State private var resolveTask: Task<Void, Never>?
    @State private var cameraAuth: ScanCameraAuthState = .undetermined
    @State private var celebration: CelebrationCenter.PendingCelebration?
    @Namespace private var glassNamespace

    init() {}

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            scannerSurface
            overlayChrome

            // The Can Drop celebration plays over the frozen camera, then
            // dismisses the whole scanner on its way out.
            if let celebration {
                CelebrationView(
                    sku: celebration.sku,
                    result: celebration.result,
                    weekCount: celebration.weekCount,
                    todayCount: celebration.todayCount,
                    streak: celebration.streak
                ) {
                    dismiss()
                }
                .transition(.opacity)
            }
        }
        .task { await requestCameraAccess() }
        .onDisappear { resolveTask?.cancel() }
        .sheet(isPresented: $showManualLog) { ManualLogSheet() }
        .preferredColorScheme(.dark)
    }

    // MARK: Camera / surface

    @ViewBuilder
    private var scannerSurface: some View {
        #if targetEnvironment(simulator)
        ScanSimulatorList(skus: skus, isFrozen: phase != .scanning) { code in
            handleScan(code)
        }
        #else
        switch cameraAuth {
        case .authorized:
            ZStack {
                cameraView.ignoresSafeArea()
                ScanViewfinderOverlay(pulsing: phase == .scanning)
                    .ignoresSafeArea()
            }
        case .denied:
            ScanPermissionDeniedView {
                showManualLog = true
            }
        case .undetermined:
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Theme.energyYellow)
                MicroLabel(text: "WARMING UP THE CAMERA")
            }
        }
        #endif
    }

    #if !targetEnvironment(simulator)
    @ViewBuilder
    private var cameraView: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            DataScannerRepresentable(isActive: isCameraActive) { code in
                handleScan(code)
            }
        } else {
            FallbackScannerView(isActive: isCameraActive) { code in
                handleScan(code)
            }
        }
    }
    #endif

    private var isCameraActive: Bool {
        // Frozen while a result/celebration is up AND while the manual-log
        // sheet covers the scanner — a barcode wandering past must not
        // hijack state underneath it.
        phase == .scanning && !didLog && !showManualLog && celebration == nil
    }

    private var showsHint: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return cameraAuth == .authorized
        #endif
    }

    // MARK: Chrome

    private var overlayChrome: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
            Spacer()
            bottomStack
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Close scanner")

            Spacer()
            MicroLabel(text: "SCANNER")
            Spacer()

            Button {
                Haptics.tick()
                showManualLog = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Log a can manually")
        }
    }

    private var bottomStack: some View {
        GlassEffectContainer(spacing: 24) {
            Group {
                switch phase {
                case .scanning:
                    if showsHint {
                        scanningHint
                    }
                case .resolving:
                    resolvingCard
                case .found(let sku):
                    resultCard(for: sku)
                case .rejected(let name):
                    rejectionCard(detectedName: name)
                case .unavailable(let code):
                    unavailableCard(code: code)
                }
            }
            .transition(cardTransition)
        }
        .animation(motionAnimation, value: phase)
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var motionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : Theme.spring
    }

    // MARK: Phase cards

    private var scanningHint: some View {
        Text("Aim at the barcode. It knows what it did.")
            .font(Theme.label(13))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("scan-card", in: glassNamespace)
    }

    private var resolvingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(Theme.energyYellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not in the fridge.")
                    .font(Theme.label(14))
                    .foregroundStyle(.white)
                Text("Asking the internet…")
                    .font(Theme.label(12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button("Cancel") {
                Haptics.tick()
                rescan()
            }
            .font(Theme.label(12))
            .buttonStyle(.glass)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardRadius))
        .glassEffectID("scan-card", in: glassNamespace)
    }

    private func resultCard(for sku: SKU) -> some View {
        let display = selectedSKU ?? sku
        // One segment per size, verified SKUs winning any collision with an
        // unverified Open-Food-Facts twin of the same flavor + size.
        var seenSizes = Set<Int>()
        let sizeOptions = skus
            .filter { $0.flavor == display.flavor }
            .sorted { a, b in
                if a.sizeML != b.sizeML { return a.sizeML < b.sizeML }
                let aIsDisplay = a.persistentModelID == display.persistentModelID
                let bIsDisplay = b.persistentModelID == display.persistentModelID
                if aIsDisplay != bIsDisplay { return aIsDisplay }
                return a.verified && !b.verified
            }
            .filter { seenSizes.insert($0.sizeML).inserted }

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                MicroLabel(text: "CAN IDENTIFIED")
                Spacer()
                CanChip(sku: display)
            }

            HStack(spacing: 16) {
                CanArtwork(sku: display, height: 108, floating: false)
                VStack(alignment: .leading, spacing: 8) {
                    Text(display.name)
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 14) {
                        statBadge(value: display.sizeLabel, label: "SIZE")
                        statBadge(value: "\(display.caffeineMG)mg", label: "CAFFEINE")
                        statBadge(value: sugarLabel(for: display), label: "SUGAR")
                    }
                    if !display.verified {
                        Text("Unverified can. Numbers are best guesses.")
                            .font(Theme.label(10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }

            if sizeOptions.count > 1 {
                ScanSizeSelector(options: sizeOptions, selection: sizeBinding)
            }

            if let saveErrorLine {
                Text(saveErrorLine)
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.bullRed)
                    .frame(maxWidth: .infinity)
            }

            if !didLog {
                Button {
                    confirm()
                } label: {
                    Text("CONFIRM")
                        .font(Theme.label(16))
                        .kerning(3)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(display.accent.opacity(0.22)), in: .rect(cornerRadius: Theme.cardRadius))
        .glassEffectID("scan-card", in: glassNamespace)
        .animation(motionAnimation, value: selectedSKU)
    }

    private func rejectionCard(detectedName: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "SCAN REJECTED")
            Text(Copy.notARedBull)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            if let detectedName, !detectedName.isEmpty {
                Text("The evidence says: \(detectedName).")
                    .font(Theme.label(12))
                    .foregroundStyle(.white.opacity(0.55))
            }

            MicroLabel(text: "OR PICK THE TRUTH BY HAND")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(ScanCatalog.flavorRepresentatives(from: skus)) { flavorSKU in
                        ScanFlavorTile(sku: flavorSKU, compact: true) {
                            Haptics.tick()
                            selectedSKU = flavorSKU
                            phase = .found(flavorSKU)
                        }
                    }
                }
                .padding(2)
            }
            .frame(maxHeight: 220)
            .scrollIndicators(.hidden)

            Button {
                Haptics.tick()
                rescan()
            } label: {
                Label("Scan again", systemImage: "barcode.viewfinder")
                    .font(Theme.label(14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        }
        .padding(20)
        .glassEffect(.regular.tint(Theme.bullRed.opacity(0.18)), in: .rect(cornerRadius: Theme.cardRadius))
        .glassEffectID("scan-card", in: glassNamespace)
    }

    /// The lookup failed, not the can. Different card, different tone.
    private func unavailableCard(code: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "LOOKUP FAILED")
            Text("The internet flaked. Not the can's fault.")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Scan again when you're back online, or log it by hand.")
                .font(Theme.label(12))
                .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 10) {
                Button {
                    Haptics.tick()
                    phase = .resolving(code)
                    resolveTask?.cancel()
                    resolveTask = Task { await resolveUnknown(code) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(Theme.label(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)

                Button {
                    Haptics.tick()
                    showManualLog = true
                } label: {
                    Label("Log by hand", systemImage: "hand.tap")
                        .font(Theme.label(14))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }

            Button {
                Haptics.tick()
                rescan()
            } label: {
                Label("Scan again", systemImage: "barcode.viewfinder")
                    .font(Theme.label(13))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
        }
        .padding(20)
        .glassEffect(.regular.tint(Theme.racingBlue.opacity(0.18)), in: .rect(cornerRadius: Theme.cardRadius))
        .glassEffectID("scan-card", in: glassNamespace)
    }

    private func statBadge(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(Theme.label(8))
                .kerning(1)
                .foregroundStyle(.white.opacity(0.45))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label.lowercased()) \(value)")
    }

    private func sugarLabel(for sku: SKU) -> String {
        if sku.sugarFree { return "0g" }
        return sku.sugarG.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(sku.sugarG))g"
            : String(format: "%.1fg", sku.sugarG)
    }

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

    // MARK: Actions

    private func handleScan(_ code: String) {
        guard phase == .scanning, !didLog else { return }
        Haptics.thump()
        if let sku = ScanCatalog.matchSKU(code: code, in: skus) {
            selectedSKU = sku
            phase = .found(sku)
        } else {
            phase = .resolving(code)
            resolveTask?.cancel()
            resolveTask = Task { await resolveUnknown(code) }
        }
    }

    private func resolveUnknown(_ code: String) async {
        let lookup = await OpenFoodFactsClient.fetch(barcode: code)
        guard !Task.isCancelled, phase == .resolving(code) else { return }
        switch lookup {
        case .found(let product) where product.isRedBull:
            let sku = OpenFoodFactsClient.makeSKU(from: product, context: modelContext)
            Haptics.thump()
            selectedSKU = sku
            phase = .found(sku)
        case .found(let product):
            Haptics.warning()
            phase = .rejected(product.name)
        case .notFound:
            Haptics.warning()
            phase = .rejected(nil)
        case .unavailable:
            // Offline or the API flaked — never accuse the can.
            Haptics.warning()
            phase = .unavailable(code)
        }
    }

    private func rescan() {
        resolveTask?.cancel()
        selectedSKU = nil
        didLog = false
        saveErrorLine = nil
        phase = .scanning
    }

    private func confirm() {
        guard let sku = selectedSKU, !didLog else { return }
        let result = LogPipeline.log(sku: sku, source: .scan, context: modelContext)

        guard result.persisted else {
            Haptics.warning()
            saveErrorLine = "That one didn't save. Try again."
            return
        }

        Haptics.success()
        didLog = true
        saveErrorLine = nil

        // Hand the numbers to the Can Drop celebration (post-log state).
        let allLogs = (try? modelContext.fetch(FetchDescriptor<CanLog>())) ?? []
        withAnimation(.easeIn(duration: 0.12)) {
            celebration = CelebrationCenter.PendingCelebration(
                sku: sku,
                result: result,
                weekCount: StatsEngine.weekCount(allLogs, weekOf: .now),
                todayCount: StatsEngine.todayCount(allLogs),
                streak: StatsEngine.currentStreak(allLogs)
            )
        }
    }

    private func requestCameraAccess() async {
        #if targetEnvironment(simulator)
        cameraAuth = .authorized
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAuth = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuth = granted ? .authorized : .denied
        default:
            cameraAuth = .denied
        }
        #endif
    }
}

// MARK: - Viewfinder overlay

/// Dims everything outside the scan window and draws pulsing yellow corner brackets.
struct ScanViewfinderOverlay: View {
    /// True while actively scanning; false freezes the brackets (result card is up).
    let pulsing: Bool

    private let windowSize = CGSize(width: 300, height: 190)
    private let windowOffsetY: CGFloat = -70
    private let windowRadius: CGFloat = 34

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .mask {
                    Rectangle()
                        .overlay {
                            RoundedRectangle(cornerRadius: windowRadius)
                                .frame(width: windowSize.width, height: windowSize.height)
                                .offset(y: windowOffsetY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }

            RoundedRectangle(cornerRadius: windowRadius)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                .frame(width: windowSize.width, height: windowSize.height)
                .offset(y: windowOffsetY)

            ScanPulsingBrackets(active: pulsing)
                .frame(width: windowSize.width + 16, height: windowSize.height + 16)
                .offset(y: windowOffsetY)
                .id(pulsing) // recreate so the repeatForever animation resets cleanly
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScanPulsingBrackets: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ScanCornerBrackets(cornerRadius: 30, armLength: 26)
            .stroke(Theme.energyYellow, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .opacity(currentOpacity)
            .scaleEffect(currentScale)
            .onAppear {
                if active && !reduceMotion {
                    withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                } else {
                    pulse = true
                }
            }
    }

    private var currentOpacity: Double {
        guard active else { return 0.4 }
        guard !reduceMotion else { return 1 }
        return pulse ? 1 : 0.35
    }

    private var currentScale: CGFloat {
        guard active, !reduceMotion else { return 1 }
        return pulse ? 1.0 : 0.955
    }
}

/// Four L-shaped corner brackets with rounded corners, drawn as one stroked path.
struct ScanCornerBrackets: Shape {
    var cornerRadius: CGFloat = 28
    var armLength: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = cornerRadius
        let a = armLength

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r + a))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r + a, y: rect.minY))

        // Top-right
        p.move(to: CGPoint(x: rect.maxX - r - a, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r + a))

        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - r - a))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r - a, y: rect.maxY))

        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + r + a, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r - a))

        return p
    }
}

// MARK: - Size selector

/// Glass segmented control listing every SKU that shares a flavor, by size.
struct ScanSizeSelector: View {
    let options: [SKU]
    @Binding var selection: SKU?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button {
                    selection = option
                } label: {
                    Text(option.sizeLabel)
                        .font(Theme.label(13))
                        .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                Capsule().fill(Theme.energyYellow)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Size \(option.sizeLabel)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Theme.spring, value: selection)
    }
}

// MARK: - Flavor tile (shared with ManualLogSheet + rejection fallback grid)

struct ScanFlavorTile: View {
    let sku: SKU
    var compact: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ScanMiniCanGlyph(accent: sku.accent, height: compact ? 44 : 64)
                Text(sku.flavor)
                    .font(Theme.label(compact ? 10 : 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 10 : 14)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(sku.accent.opacity(0.28)).interactive(), in: .rect(cornerRadius: 20))
        .accessibilityLabel("\(sku.flavor) flavor")
    }
}

/// Tiny stylized can silhouette — accent gradient body, silver rim, slanted stripe.
/// Deliberately cheap (no motion) so it can live in grids.
struct ScanMiniCanGlyph: View {
    let accent: Color
    var height: CGFloat = 44

    var body: some View {
        let width = height * 0.6
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.28)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.95), accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(width: width * 1.6, height: height * 0.16)
                .rotationEffect(.degrees(-24))
            Ellipse()
                .fill(Theme.silver.opacity(0.9))
                .frame(width: width * 0.72, height: height * 0.10)
                .offset(y: -height * 0.44)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.28))
        .accessibilityHidden(true)
    }
}

// MARK: - Permission denied

struct ScanPermissionDeniedView: View {
    let openManualLog: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(Theme.energyYellow)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("No camera, no scan.")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Settings can fix that.")
                    .font(Theme.label(14))
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack(spacing: 10) {
                Button {
                    Haptics.tick()
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("OPEN SETTINGS")
                        .font(Theme.label(14))
                        .kerning(2)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.energyYellow)

                Button {
                    Haptics.tick()
                    openManualLog()
                } label: {
                    Text("Log it manually instead")
                        .font(Theme.label(13))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 8)
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardRadius))
        .padding(.horizontal, 28)
    }
}

// MARK: - Simulator debug scan list

/// Simulator has no camera, so we fake it: tap a can to run the exact same
/// recognition path a real scan would take.
struct ScanSimulatorList: View {
    let skus: [SKU]
    let isFrozen: Bool
    let simulate: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MicroLabel(text: "SIMULATOR MODE")
                Text("No camera in here. Tap a can to fake the scan.")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if skus.isEmpty {
                    Text("No SKUs seeded yet. The fridge database is empty — check SeedLoader.")
                        .font(Theme.label(12))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 8)
                }

                ForEach(skus) { sku in
                    Button {
                        simulate(sku.barcode)
                    } label: {
                        HStack(spacing: 12) {
                            CanChip(sku: sku)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sku.name)
                                    .font(Theme.label(13))
                                    .foregroundStyle(.white)
                                Text("\(sku.flavor) · \(sku.sizeLabel)")
                                    .font(Theme.label(11))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            Spacer()
                            Text(sku.barcode)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }

                Button {
                    simulate("5449000000996") // a famously-not-Red-Bull barcode
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(Theme.bullRed)
                            .accessibilityHidden(true)
                        Text("Simulate a mystery barcode (not a Red Bull)")
                            .font(Theme.label(12))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.bullRed.opacity(0.15)), in: .rect(cornerRadius: 20))
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 280)
        }
        .scrollIndicators(.hidden)
        .disabled(isFrozen)
        .opacity(isFrozen ? 0.45 : 1)
    }
}
