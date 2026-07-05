import SwiftUI
import CoreMotion

// MARK: - CanPalette

/// Everything needed to paint a can (and its celebration) for one flavor,
/// ported verbatim from the Claude Design "Can Drop Celebration" prototype.
/// Purple/Blue/Red Editions use the design's hand-tuned gradients; silver
/// families use the design's aluminum ramp; everything else derives from the
/// SKU's accent color in HSB space so new flavors land on-brand for free.
struct CanPalette {
    /// Five-stop horizontal body gradient at [0, 0.28, 0.46, 0.70, 1.0]:
    /// dark edge → mid → bright center-left → mid → dark edge.
    let bodyStops: [Color]
    /// Diagonal stripe tint (a pale version of the flavor).
    let stripe: Color
    /// The word printed on the stripe (PURPLE / BLUE / ENERGY / …).
    let word: String
    /// Celebration flood circle color.
    let flood: Color
    /// Stage-light center for the flooded backdrop.
    let bright: Color
    /// Stage-light edges for the flooded backdrop.
    let deep: Color

    static let bodyStopLocations: [CGFloat] = [0, 0.28, 0.46, 0.70, 1.0]

    var bodyGradient: LinearGradient {
        LinearGradient(
            stops: zip(bodyStops, Self.bodyStopLocations).map { .init(color: $0, location: $1) },
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Design's aluminum ramp (silver Original can).
    static let silverStops = ["#4d545c", "#aab2bc", "#dfe5ea", "#868f99", "#3f454c"].map { Color(hex: $0) }

    static func palette(for sku: SKU?) -> CanPalette {
        guard let sku else {
            // The mascot silver Original with the racing-blue stripe.
            return CanPalette(
                bodyStops: silverStops,
                stripe: Color(hex: "#2E5FDF"),
                word: "ENERGY",
                flood: Color(hex: "#2E5FDF"),
                bright: Color(hex: "#4A7BFF"),
                deep: Color(hex: "#122B72")
            )
        }

        let word = canWord(for: sku)

        // Hand-tuned design gradients for the three prototype editions.
        switch sku.canStyle {
        case "acai", "açaí":
            return CanPalette(
                bodyStops: ["#2a1547", "#7a3fb5", "#a86fdd", "#5f2f96", "#1f0f38"].map { Color(hex: $0) },
                stripe: Color(hex: "#c9b3e8"), word: word,
                flood: Color(hex: "#7B2FBE"), bright: Color(hex: "#9540DB"), deep: Color(hex: "#3E1466")
            )
        case "blueberry":
            return CanPalette(
                bodyStops: ["#0a1f4d", "#2E5FDF", "#7fa3ff", "#1d3f9f", "#071733"].map { Color(hex: $0) },
                stripe: Color(hex: "#bcd0ff"), word: word,
                flood: Color(hex: "#2E5FDF"), bright: Color(hex: "#4A7BFF"), deep: Color(hex: "#122B72")
            )
        case "watermelon":
            return CanPalette(
                bodyStops: ["#4d0316", "#c40a3a", "#ff5c82", "#8f0629", "#33020e"].map { Color(hex: $0) },
                stripe: Color(hex: "#ffc9d6"), word: word,
                flood: Color(hex: "#DB0A40"), bright: Color(hex: "#F53063"), deep: Color(hex: "#6E0521")
            )
        default:
            break
        }

        // Silver families: aluminum body, flavor-accented stripe.
        if sku.lineup == "original" || sku.lineup == "sugarfree" || sku.lineup == "zero" {
            let accent = sku.accent
            return CanPalette(
                bodyStops: silverStops,
                stripe: sku.lineup == "original" ? Color(hex: "#2E5FDF") : accent,
                word: word,
                flood: accent.canMixed(with: Color(hex: "#2E5FDF"), amount: 0.5),
                bright: accent.canAdjusted(brightness: 1.15),
                deep: accent.canAdjusted(saturation: 1.05, brightness: 0.35)
            )
        }

        // Derived edition palette from the accent, matching the design's shape:
        // dark edge / mid / bright 46% / mid / dark edge.
        let accent = sku.accent
        return CanPalette(
            bodyStops: [
                accent.canAdjusted(saturation: 1.15, brightness: 0.30),
                accent.canAdjusted(brightness: 0.80),
                accent.canAdjusted(saturation: 0.75, brightness: 1.18),
                accent.canAdjusted(brightness: 0.60),
                accent.canAdjusted(saturation: 1.15, brightness: 0.22),
            ],
            stripe: accent.canMixed(with: .white, amount: 0.65),
            word: word,
            flood: accent,
            bright: accent.canAdjusted(brightness: 1.22),
            deep: accent.canAdjusted(saturation: 1.1, brightness: 0.4)
        )
    }

    /// PURPLE from "Red Bull Purple Edition", SUGARFREE, ZERO, ENERGY.
    private static func canWord(for sku: SKU) -> String {
        let name = sku.name
        if let range = name.range(of: " Edition") {
            let head = name[..<range.lowerBound]
            if let editionWord = head.split(separator: " ").last {
                return editionWord.uppercased()
            }
        }
        switch sku.lineup {
        case "sugarfree": return "SUGARFREE"
        case "zero": return "ZERO"
        case "original": return "ENERGY"
        default: return sku.flavor.split(separator: " ").first.map { $0.uppercased() } ?? "ENERGY"
        }
    }
}

extension Color {
    /// HSB-space tweak used to derive edition can gradients from an accent.
    nonisolated func canAdjusted(saturation satScale: CGFloat = 1, brightness briScale: CGFloat = 1) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(1, s * satScale), brightness: min(1, b * briScale), opacity: a)
    }

    nonisolated func canMixed(with other: Color, amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let t = CGFloat(amount)
        return Color(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t
        )
    }
}

// MARK: - DesignCan

/// The can, layer-for-layer from the design prototype:
/// silver elliptical lid → five-stop cylindrical body → two -18° stripes →
/// stripe word → cylindrical shading → sweeping specular sheen ("the glint").
/// `sheenPhase` in [0, 1) drives the glint sweep; pass nil for a static can.
struct DesignCan: View {
    let palette: CanPalette
    let sheenPhase: Double?
    var showWord: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let lidH = h * 0.061
            let bodyTop = h * 0.032

            ZStack(alignment: .top) {
                // Body
                bodyLayer(w: w, h: h - bodyTop, lidH: lidH)
                    .offset(y: bodyTop)

                // Lid: linear-gradient(90deg, #5a636d, #c6cdd5 45%, #6b747e)
                Ellipse()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(hex: "#5a636d"), location: 0),
                                .init(color: Color(hex: "#c6cdd5"), location: 0.45),
                                .init(color: Color(hex: "#6b747e"), location: 1),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        // inset 0 -2px shadow: darker lower lip on the lid
                        Ellipse()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.5)],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: w * 0.82, height: lidH * 2)
                    .position(x: w / 2, y: lidH)
            }
        }
        .accessibilityHidden(true)
    }

    private func bodyLayer(w: CGFloat, h: CGFloat, lidH: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: w * 0.18,
            bottomLeadingRadius: w * 0.20,
            bottomTrailingRadius: w * 0.20,
            topTrailingRadius: w * 0.18,
            style: .continuous
        )

        return ZStack {
            // Five-stop cylindrical flavor gradient
            shape.fill(palette.bodyGradient)

            ZStack {
                // Two -18° stripes: heights 16.8% / 6.4%, tops 36% / 54%,
                // opacities .78 / .42 — straight from the prototype CSS.
                Rectangle()
                    .fill(palette.stripe)
                    .opacity(0.78)
                    .frame(width: w * 2.4, height: h * 0.168)
                    .rotationEffect(.degrees(-18))
                    .position(x: w / 2, y: h * 0.44)

                Rectangle()
                    .fill(palette.stripe)
                    .opacity(0.42)
                    .frame(width: w * 2.4, height: h * 0.064)
                    .rotationEffect(.degrees(-18))
                    .position(x: w / 2, y: h * 0.60)

                // The word rides the big stripe
                if showWord {
                    Text(palette.word)
                        .font(.system(size: h * 0.059, weight: .black, design: .rounded))
                        .kerning(h * 0.0114)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.35), radius: h * 0.014, y: h * 0.0045)
                        .rotationEffect(.degrees(-18))
                        .position(x: w / 2, y: h * 0.50)
                        .frame(maxWidth: .infinity)
                }

                // Cylindrical shading:
                // 90deg black.38 → white.28 @32% → clear @55% → black.45
                Rectangle().fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.38), location: 0),
                            .init(color: .white.opacity(0.28), location: 0.32),
                            .init(color: .white.opacity(0), location: 0.55),
                            .init(color: .black.opacity(0.45), location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                // The glint: 115° highlight band sweeping across (ccSheen)
                if let sheenPhase {
                    sheen(w: w, h: h, phase: sheenPhase)
                } else {
                    sheen(w: w, h: h, phase: 0.42)
                }
            }
            // Pin to the can's exact bounds BEFORE clipping: the sheen band is
            // 1.6× wider than the can, and without this the ZStack union (and
            // therefore the clip shape) inflates to the sheen's width — the
            // fat-can bug caught on the first celebration recording.
            .frame(width: w, height: h)
            .clipShape(shape)

            // inset 0 2px 0 rgba(255,255,255,.4) — lit top edge
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.4), .white.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: max(0.8, w * 0.008)
            )
        }
        .frame(width: w, height: h)
    }

    /// linear-gradient(115deg, transparent 34%, white .34 44%, white .04 52%,
    /// transparent 60%) with background-position swept 220% → -120%.
    private func sheen(w: CGFloat, h: CGFloat, phase: Double) -> some View {
        // Ease-in-out on the sweep, then map to an x offset across the can.
        let eased = phase < 0.5 ? 2 * phase * phase : 1 - pow(-2 * phase + 2, 2) / 2
        let x = w * (1.7 - 2.9 * eased)
        return Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.34),
                        .init(color: .white.opacity(0.34), location: 0.44),
                        .init(color: .white.opacity(0.04), location: 0.52),
                        .init(color: .clear, location: 0.60),
                    ],
                    startPoint: UnitPoint(x: 0.08, y: 0.28),   // ≈115°
                    endPoint: UnitPoint(x: 0.92, y: 0.72)
                )
            )
            .frame(width: w * 1.6, height: h)
            .offset(x: x)
    }
}

// MARK: - CanArtwork

/// The floating hero can. Verbatim design motion:
/// - ccFloat: 4.5s levitation, y 0 → -14 and tilt -4° → -2°
/// - ccGlow: the yellow ground pool breathes in counterphase
/// - ccSheen: the glint sweeps every 5.5s
/// plus CoreMotion parallax tilt on device. All of it timeline-driven, so it
/// survives tab switches and vanishes entirely under Reduce Motion.
struct CanArtwork: View {
    let sku: SKU?
    let height: CGFloat
    let floating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motionActive = false

    private let motion = ParallaxMotion.shared

    init(sku: SKU?, height: CGFloat = 260, floating: Bool = true) {
        self.sku = sku
        self.height = height
        self.floating = floating
    }

    // Design proportions: 88 × 196 → width ≈ 0.449 × height.
    private var canHeight: CGFloat { floating ? height * 0.90 : height }
    private var canWidth: CGFloat { canHeight * 0.449 }
    private var palette: CanPalette { CanPalette.palette(for: sku) }

    private var animating: Bool { floating && !reduceMotion }

    var body: some View {
        Group {
            if animating {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    composed(at: t)
                }
            } else {
                composed(at: nil)
            }
        }
        .frame(width: floating ? canWidth * 1.7 : canWidth, height: height)
        .onAppear(perform: startMotionIfNeeded)
        .onDisappear(perform: stopMotionIfNeeded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sku.map { "\($0.name) can" } ?? "Red Bull can")
    }

    /// One frame of the hero. `t == nil` renders the static (Reduce Motion /
    /// chip) pose.
    private func composed(at t: TimeInterval?) -> some View {
        // ccFloat: 0%/100% → y0 rot-4°; 50% → y-14 rot-2° (4.5s ease-in-out)
        let floatPhase = t.map { ($0.truncatingRemainder(dividingBy: 4.5)) / 4.5 } ?? 0
        let wave = cos(2 * .pi * floatPhase)   // 1 at rest, -1 at apex
        let yOffset = t == nil ? 0 : -(height * 0.036) * (1 - wave)
        let tilt = floating ? (t == nil ? -3.0 : -3.0 - wave) : 0
        // ccSheen: 5.5s sweep
        let sheenPhase = t.map { ($0.truncatingRemainder(dividingBy: 5.5)) / 5.5 }
        // ccGlow: opacity .55↔.85, width 1↔1.12 in counterphase
        let glowOpacity = t == nil ? 0.7 : 0.7 - 0.15 * wave
        let glowScaleX = t == nil ? 1.06 : 1.06 - 0.06 * wave

        return ZStack(alignment: .bottom) {
            if floating {
                ZStack {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [Theme.energyYellow.opacity(0.5), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: canWidth * 0.75
                            )
                        )
                        .frame(width: canWidth * 1.48, height: canWidth * 0.30)
                        .blur(radius: 8)
                        .scaleEffect(x: glowScaleX, y: 1)
                        .opacity(glowOpacity)
                    Ellipse()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: canWidth * 0.95, height: canWidth * 0.20)
                        .blur(radius: 5)
                }
                .accessibilityHidden(true)
            }

            DesignCan(palette: palette, sheenPhase: sheenPhase, showWord: canHeight >= 120)
                .frame(width: canWidth, height: canHeight)
                .shadow(color: .black.opacity(0.55), radius: canHeight * 0.09, y: canHeight * 0.041)
                .rotationEffect(.degrees(tilt))
                .offset(y: yOffset)
                .rotation3DEffect(
                    .radians(animating ? motion.roll * 0.22 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .radians(animating ? -motion.pitch * 0.22 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .padding(.bottom, floating ? canWidth * 0.16 : 0)
        }
    }

    private func startMotionIfNeeded() {
        guard animating else { return }
        motion.begin()
        motionActive = true
    }

    private func stopMotionIfNeeded() {
        guard motionActive else { return }
        motion.end()
        motionActive = false
    }
}

// MARK: - CanChip

/// A small rounded flavor chip for log rows — reads as a miniature can:
/// silver lid strip over a flavor-accent body with cylindrical shading.
struct CanChip: View {
    let sku: SKU

    init(sku: SKU) {
        self.sku = sku
    }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color(hex: "#EDF1F5"), Color(hex: "#8A929B")],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 7)
            Rectangle()
                .fill(CanPalette.palette(for: sku).bodyGradient)
        }
        .frame(width: 22, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.8)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sku.flavor) can")
    }
}

// MARK: - Shared parallax motion source

/// One `CMMotionManager` for the whole app (Apple recommends a single
/// instance). Views call `begin()` / `end()`; updates stop when the last
/// client leaves. Publishes smoothed pitch/roll deltas (radians) relative to
/// the attitude when tracking began. Inert in the Simulator and on devices
/// without device-motion hardware.
@Observable
final class ParallaxMotion {
    static let shared = ParallaxMotion()

    private(set) var pitch: Double = 0
    private(set) var roll: Double = 0

    private let manager = CMMotionManager()
    private var referencePitch: Double?
    private var referenceRoll: Double?
    private var clients = 0

    private init() {}

    func begin() {
        clients += 1
        guard clients == 1 else { return }
        #if targetEnvironment(simulator)
        // No gyro in the Simulator — the can skips the parallax flourish.
        #else
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { @Sendable [weak self] deviceMotion, _ in
            guard let deviceMotion else { return }
            // Pull the primitives out before the actor hop — CMDeviceMotion
            // itself is not Sendable (Release-config strict-concurrency error).
            let rawPitch = deviceMotion.attitude.pitch
            let rawRoll = deviceMotion.attitude.roll
            MainActor.assumeIsolated {
                self?.ingest(pitch: rawPitch, roll: rawRoll)
            }
        }
        #endif
    }

    func end() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        #if !targetEnvironment(simulator)
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        #endif
        referencePitch = nil
        referenceRoll = nil
        pitch = 0
        roll = 0
    }

    private func ingest(pitch rawPitch: Double, roll rawRoll: Double) {
        if referencePitch == nil {
            referencePitch = rawPitch
            referenceRoll = rawRoll
        }
        let dp = clamped(rawPitch - (referencePitch ?? 0))
        let dr = clamped(rawRoll - (referenceRoll ?? 0))
        // Low-pass so the can glides instead of jittering.
        pitch = pitch * 0.85 + dp * 0.15
        roll = roll * 0.85 + dr * 0.15
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, -0.6), 0.6)
    }
}

// MARK: - Previews

#Preview("Hero can — Original") {
    ZStack {
        Theme.canvas.ignoresSafeArea()
        CanArtwork(sku: nil)
    }
    .preferredColorScheme(.dark)
}

#Preview("Mini can — static") {
    ZStack {
        Theme.canvas.ignoresSafeArea()
        CanArtwork(sku: nil, height: 90, floating: false)
    }
    .preferredColorScheme(.dark)
}
