import SwiftUI

/// Celebration overlay. Each time `trigger` increments, ~80 particles —
/// yellow / racing-blue / silver capsules, circles, and tiny can-shaped
/// rects — burst from just above center, fly out, fall under gravity with
/// horizontal drift and spin, and fade over ~1.6 seconds.
///
/// Deterministic: particle seeds derive purely from the trigger value, so a
/// given trigger always produces the same burst. Non-interactive
/// (`allowsHitTesting(false)`), and skipped entirely under Reduce Motion.
///
/// Usage: keep an `Int` in state, overlay `ConfettiBurst(trigger: count)`,
/// and increment the count whenever something worth celebrating happens.
struct ConfettiBurst: View {
    let trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstStart: Date?
    @State private var particles: [Particle] = []
    @State private var generation = 0

    fileprivate static let duration: TimeInterval = 1.6
    fileprivate static let gravity: Double = 950
    private static let particleCount = 80

    /// Yellow weighted heaviest — it is the brand moment, after all.
    fileprivate static let palette: [Color] = [
        Theme.energyYellow,
        Theme.energyYellow,
        Theme.racingBlue,
        Color(hex: "#5B85F0"),
        Theme.silver,
    ]

    init(trigger: Int) {
        self.trigger = trigger
    }

    var body: some View {
        ZStack {
            if !reduceMotion, burstStart != nil {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Canvas { context, size in
                        guard let start = burstStart else { return }
                        let t = timeline.date.timeIntervalSince(start)
                        guard t >= 0, t <= Self.duration else { return }
                        let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                        for particle in particles {
                            particle.draw(in: context, at: t, origin: origin)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { oldValue, newValue in
            guard newValue != oldValue, !reduceMotion else { return }
            fire(seed: newValue)
        }
    }

    private func fire(seed: Int) {
        particles = Self.makeParticles(seed: seed)
        burstStart = .now
        generation += 1
        let current = generation
        Task {
            try? await Task.sleep(for: .seconds(Self.duration + 0.15))
            // Only tear down if a newer burst hasn't replaced this one.
            if generation == current {
                burstStart = nil
                particles = []
            }
        }
    }

    // MARK: - Particle generation (deterministic per trigger)

    private static func makeParticles(seed: Int) -> [Particle] {
        var rng = SplitMix64(
            seed: UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
        )
        return (0..<particleCount).map { _ in
            let angle = Double.random(in: 0..<(2 * .pi), using: &rng)
            let speed = Double.random(in: 90...420, using: &rng)
            let kindRoll = Double.random(in: 0..<1, using: &rng)
            let kind: Particle.Kind = kindRoll < 0.40 ? .capsule : (kindRoll < 0.72 ? .circle : .can)
            return Particle(
                kind: kind,
                colorIndex: Int.random(in: 0..<palette.count, using: &rng),
                vx: cos(angle) * speed,
                vy: sin(angle) * speed - Double.random(in: 200...420, using: &rng),
                windAX: Double.random(in: -70...70, using: &rng),
                spin: Double.random(in: -9...9, using: &rng),
                rot0: Double.random(in: 0..<(2 * .pi), using: &rng),
                sizeScale: Double.random(in: 0.7...1.35, using: &rng),
                delay: Double.random(in: 0...0.12, using: &rng)
            )
        }
    }
}

// MARK: - Particle

private struct Particle {
    enum Kind {
        case capsule, circle, can
    }

    let kind: Kind
    let colorIndex: Int
    let vx: Double        // launch velocity, pts/s
    let vy: Double        // negative = upward
    let windAX: Double    // horizontal drift acceleration, pts/s²
    let spin: Double      // rad/s
    let rot0: Double      // initial rotation, rad
    let sizeScale: Double
    let delay: Double     // stagger, seconds

    func draw(in context: GraphicsContext, at time: TimeInterval, origin: CGPoint) {
        let te = time - delay
        guard te > 0 else { return }
        let life = ConfettiBurst.duration - delay
        guard life > 0 else { return }
        let progress = te / life
        guard progress < 1 else { return }

        let x = origin.x + CGFloat(vx * te + 0.5 * windAX * te * te)
        let y = origin.y + CGFloat(vy * te + 0.5 * ConfettiBurst.gravity * te * te)
        let appear = min(1.0, te / 0.1)
        let fade = progress < 0.7 ? 1.0 : max(0.0, 1.0 - (progress - 0.7) / 0.3)

        var ctx = context
        ctx.translateBy(x: x, y: y)
        ctx.rotate(by: .radians(rot0 + spin * te))
        let s = CGFloat(appear * sizeScale)
        ctx.scaleBy(x: s, y: s)
        ctx.opacity = fade

        let color = ConfettiBurst.palette[colorIndex]
        switch kind {
        case .capsule:
            let rect = CGRect(x: -5.5, y: -2.25, width: 11, height: 4.5)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2.25), with: .color(color))
        case .circle:
            let rect = CGRect(x: -3.2, y: -3.2, width: 6.4, height: 6.4)
            ctx.fill(Path(ellipseIn: rect), with: .color(color))
        case .can:
            // Tiny can: colored body with a silver lid strip.
            let body = CGRect(x: -3.2, y: -5, width: 6.4, height: 10)
            ctx.fill(Path(roundedRect: body, cornerRadius: 1.8), with: .color(color))
            let lid = CGRect(x: -3.2, y: -5, width: 6.4, height: 2.4)
            ctx.fill(Path(roundedRect: lid, cornerRadius: 1.2), with: .color(Theme.silver.opacity(0.9)))
        }
    }
}

// MARK: - Deterministic RNG

/// SplitMix64 — tiny, fast, and fully determined by its seed, so a given
/// trigger value always throws the exact same party.
private nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Preview

#Preview("ConfettiBurst") {
    @Previewable @State var trigger = 0
    ZStack {
        Theme.canvas.ignoresSafeArea()
        Button("New PR") {
            trigger += 1
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.energyYellow)
    }
    .overlay(ConfettiBurst(trigger: trigger))
    .preferredColorScheme(.dark)
}
