import SwiftUI
import CoreMotion

// MARK: - CanArtwork

/// The app's hero object: a stylized Red Bull-esque can drawn entirely in
/// SwiftUI. Layered aluminum gradients, a flavor-tinted body, an elliptical
/// silver lid with a pull-tab hint, a slanted brand stripe crossing a yellow
/// sun-disc emblem (brand *suggested*, never copied), a diagonal specular
/// sheen, and — when `floating` — a soft yellow ambient glow beneath, a slow
/// idle float, and CoreMotion parallax tilt.
///
/// `sku == nil` renders the silver/blue Original. Under Reduce Motion all
/// movement (float, tilt, parallax) is disabled and the can simply hovers.
struct CanArtwork: View {
    let sku: SKU?
    let height: CGFloat
    let floating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floatUp = false
    @State private var motionActive = false

    private let motion = ParallaxMotion.shared

    init(sku: SKU?, height: CGFloat = 260, floating: Bool = true) {
        self.sku = sku
        self.height = height
        self.floating = floating
    }

    // MARK: Metrics

    private var canHeight: CGFloat { floating ? height * 0.92 : height }
    private var canWidth: CGFloat { canHeight * 0.40 }   // slim-can proportions

    // MARK: Palette

    private var bodyColor: Color { sku?.accent ?? Theme.silver }

    /// Perceived luminance of the body color, used to pick contrasting art.
    private var bodyLuminance: Double {
        guard let hex = sku?.accentHex else { return 0.78 } // Original silver
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private var isLightBody: Bool { bodyLuminance > 0.62 }

    private var stripeColors: [Color] {
        isLightBody
            ? [Theme.racingBlue, Theme.racingBlueDark]
            : [.white.opacity(0.92), Theme.silver.opacity(0.85)]
    }

    private var wordmarkColor: Color {
        isLightBody ? Theme.racingBlueDark : .white.opacity(0.94)
    }

    private var wordmark: String {
        (sku?.flavor ?? "Energy").uppercased()
    }

    private var silverLight: Color { Color(hex: "#EDF1F5") }
    private var silverMid: Color { Color(hex: "#B9C0C9") }
    private var silverDark: Color { Color(hex: "#7C858F") }

    // MARK: Motion

    private var parallaxActive: Bool { floating && !reduceMotion }

    private var parallaxRoll: Double { parallaxActive ? motion.roll * 0.22 : 0 }
    private var parallaxPitch: Double { parallaxActive ? -motion.pitch * 0.22 : 0 }

    private var floatOffset: CGFloat {
        guard floating, !reduceMotion else { return 0 }
        return floatUp ? -height * 0.030 : height * 0.012
    }

    private var idleTilt: Double {
        guard floating, !reduceMotion else { return 0 }
        return floatUp ? -1.3 : 1.3
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            if floating {
                groundGlow
            }
            can
                .rotationEffect(.degrees(idleTilt))
                .offset(y: floatOffset)
                .rotation3DEffect(
                    .radians(parallaxRoll),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .radians(parallaxPitch),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .padding(.bottom, floating ? canWidth * 0.20 : 0)
        }
        .frame(width: floating ? canWidth * 1.7 : canWidth, height: height)
        .onAppear(perform: startMotionIfNeeded)
        .onDisappear(perform: stopMotionIfNeeded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sku.map { "\($0.name) can" } ?? "Red Bull can")
    }

    private func startMotionIfNeeded() {
        guard floating, !reduceMotion else { return }
        motion.begin()
        motionActive = true
        withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true)) {
            floatUp = true
        }
    }

    private func stopMotionIfNeeded() {
        guard motionActive else { return }
        motion.end()
        motionActive = false
    }

    // MARK: Ground glow + contact shadow

    private var groundGlow: some View {
        ZStack {
            // Soft yellow ambient pool
            Ellipse()
                .fill(Theme.energyYellow.opacity(0.30))
                .frame(width: canWidth * 1.6, height: canWidth * 0.55)
                .blur(radius: canWidth * 0.13)
            // Contact shadow
            Ellipse()
                .fill(Color.black.opacity(0.50))
                .frame(width: canWidth * 1.0, height: canWidth * 0.24)
                .blur(radius: canWidth * 0.06)
        }
        // Breathes inversely with the float: shrinks slightly as the can rises.
        .scaleEffect(x: floatUp ? 0.90 : 1.0, y: floatUp ? 0.92 : 1.0)
        .opacity(floatUp ? 0.85 : 1.0)
        .accessibilityHidden(true)
    }

    // MARK: The can itself

    private var can: some View {
        let w = canWidth
        let h = canHeight
        let lidH = w * 0.24
        return ZStack(alignment: .top) {
            canBody(width: w, bodyHeight: h - lidH / 2)
                .offset(y: lidH / 2)
            canLid(width: w, lidHeight: lidH)
        }
        .frame(width: w, height: h)
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: h * 0.05, x: 0, y: h * 0.035)
    }

    private func canBody(width w: CGFloat, bodyHeight bh: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: w * 0.10,
            bottomLeadingRadius: w * 0.16,
            bottomTrailingRadius: w * 0.16,
            topTrailingRadius: w * 0.10,
            style: .continuous
        )
        return ZStack {
            // Base flavor tint
            shape.fill(bodyColor)
            // Vertical depth: lit at the shoulder, darker at the base
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.26)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Printed artwork, clipped to the can silhouette
            artwork(width: w, bodyHeight: bh)
                .clipShape(shape)
            // Cylindrical shading over the artwork so the print curves with the can
            shape.fill(cylinderShading)
            // Diagonal specular sheen
            shape.fill(specularSheen)
                .blendMode(.screen)
            // Faint rim line to catch the canvas glow
            shape.strokeBorder(.white.opacity(0.10), lineWidth: max(0.6, w * 0.012))
        }
        .compositingGroup()
        .frame(width: w, height: bh)
    }

    private var cylinderShading: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.42), location: 0.00),
                .init(color: .clear, location: 0.16),
                .init(color: .white.opacity(0.16), location: 0.30),
                .init(color: .clear, location: 0.52),
                .init(color: .black.opacity(0.10), location: 0.72),
                .init(color: .black.opacity(0.45), location: 1.00),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var specularSheen: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.30),
                .init(color: .white.opacity(0.30), location: 0.40),
                .init(color: .white.opacity(0.06), location: 0.47),
                .init(color: .clear, location: 0.55),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The "print" on the can: neck band, sun-disc emblem, slanted stripe,
    /// flavor wordmark, base shadow band.
    private func artwork(width w: CGFloat, bodyHeight bh: CGFloat) -> some View {
        ZStack {
            // Silver neck band where the body meets the lid
            Rectangle()
                .fill(LinearGradient(colors: [silverLight, silverDark], startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: bh * 0.045)
                .position(x: w / 2, y: bh * 0.0225)

            // Sun-disc emblem
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#FFE066"), Theme.energyYellow],
                        center: .center,
                        startRadius: 0,
                        endRadius: w * 0.34
                    )
                )
                .overlay(
                    Circle().strokeBorder(.white.opacity(0.30), lineWidth: max(0.5, w * 0.014))
                )
                .frame(width: w * 0.62, height: w * 0.62)
                .position(x: w / 2, y: bh * 0.33)

            // Slanted brand stripe crossing the emblem
            Rectangle()
                .fill(LinearGradient(colors: stripeColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: w * 2.4, height: bh * 0.11)
                .rotationEffect(.degrees(-24))
                .position(x: w / 2, y: bh * 0.38)

            // Flavor wordmark (skipped on mini cans where it would just blur)
            if canHeight >= 140 {
                Text(wordmark)
                    .font(.system(size: canHeight * 0.052, weight: .heavy, design: .rounded))
                    .kerning(canHeight * 0.006)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(wordmarkColor)
                    .frame(width: w * 0.92)
                    .position(x: w / 2, y: bh * 0.55)
            }

            // Base shadow band
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .black.opacity(0.38)], startPoint: .top, endPoint: .bottom))
                .frame(width: w, height: bh * 0.10)
                .position(x: w / 2, y: bh * 0.95)
        }
        .frame(width: w, height: bh)
    }

    private func canLid(width w: CGFloat, lidHeight lh: CGFloat) -> some View {
        ZStack {
            // Outer rim
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [silverLight, silverMid, silverDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // Recessed top surface
            Ellipse()
                .fill(LinearGradient(colors: [silverDark, silverMid], startPoint: .top, endPoint: .bottom))
                .scaleEffect(0.82)
            // Rim highlight
            Ellipse()
                .strokeBorder(.white.opacity(0.55), lineWidth: max(0.5, w * 0.012))
            // Pull-tab hint: ring + stem, foreshortened
            Ellipse()
                .strokeBorder(silverLight.opacity(0.9), lineWidth: max(0.6, w * 0.02))
                .frame(width: w * 0.18, height: lh * 0.42)
                .offset(x: w * 0.03, y: lh * 0.10)
            Capsule()
                .fill(silverLight)
                .frame(width: w * 0.06, height: lh * 0.34)
                .offset(x: -w * 0.055, y: -lh * 0.04)
        }
        .frame(width: w * 0.90, height: lh)
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
                .fill(sku.accent)
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.35), location: 0.00),
                            .init(color: .clear, location: 0.25),
                            .init(color: .white.opacity(0.25), location: 0.45),
                            .init(color: .clear, location: 0.65),
                            .init(color: .black.opacity(0.30), location: 1.00),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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
            MainActor.assumeIsolated {
                self?.ingest(deviceMotion)
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

    private func ingest(_ deviceMotion: CMDeviceMotion) {
        let rawPitch = deviceMotion.attitude.pitch
        let rawRoll = deviceMotion.attitude.roll
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
