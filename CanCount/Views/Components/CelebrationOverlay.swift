import SwiftUI

// MARK: - CelebrationCenter

/// Hands a pending celebration from wherever the log happened (manual sheet,
/// notification action) to RootTabView, which plays it over everything.
/// The scanner hosts CelebrationView directly inside its own full-screen
/// cover, so it never goes through the center.
@MainActor
@Observable
final class CelebrationCenter {
    static let shared = CelebrationCenter()

    struct PendingCelebration: Identifiable {
        let id = UUID()
        let sku: SKU
        let result: LogResult
        let weekCount: Int
        let todayCount: Int
        let streak: Int
    }

    var pending: PendingCelebration?

    func celebrate(sku: SKU, result: LogResult, weekCount: Int, todayCount: Int, streak: Int) {
        pending = PendingCelebration(
            sku: sku, result: result, weekCount: weekCount, todayCount: todayCount, streak: streak
        )
    }
}

// MARK: - CelebrationView

/// The "Can Drop" celebration, ported frame-for-frame from the Claude Design
/// prototype (Can Drop Celebration.dc.html). All motion derives from a single
/// clock through the prototype's exact damped-cosine formulas:
///
///   0.00–0.40  flavor circle floods the screen (42× ease-out-cubic)
///   0.40–0.62  the can freefalls in (−940 → overshoot, p² acceleration)
///   0.62+      impact: 44·e^(−5τ)·cos(14τ) bounce, 7%/6% squash-stretch,
///              2.4px screen shake, shockwave ring, carbonation bubbles
///   1.00       "CAN #N" slams in (scale 1 + 0.42·e^(−5.5t)·cos(7.5t))
///   1.25/1.45  SKU line, then the dry one-liner fade up
///   1.60       glass pill drops in; 1.75 the odometer digits roll N−1 → N
///   2.05       78-particle confetti burst (deterministic, seeded)
///   2.30       streak flame pill pops (scale 1 − 0.7·e^(−7t)·cos(9t))
///   2.50       KEEP IT COLD slides up
///   exit       flood contracts (ease-in-cubic), Home re-emerges
struct CelebrationView: View {
    let sku: SKU
    let result: LogResult
    let weekCount: Int
    let todayCount: Int
    let streak: Int
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startDate: Date?
    @State private var exitStart: Date?
    @State private var hapticsTask: Task<Void, Never>?

    init(sku: SKU, result: LogResult, weekCount: Int, todayCount: Int, streak: Int,
         onDone: @escaping () -> Void) {
        self.sku = sku
        self.result = result
        self.weekCount = weekCount
        self.todayCount = todayCount
        self.streak = streak
        self.onDone = onDone
    }

    private var palette: CanPalette { CanPalette.palette(for: sku) }

    var body: some View {
        Group {
            if reduceMotion {
                reducedMotionBody
            } else {
                TimelineView(.animation) { context in
                    let t = elapsed(at: context.date)
                    let e = exitElapsed(at: context.date)
                    GeometryReader { geo in
                        frame(t: t, exit: e, size: geo.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { beginExit() }
        .onAppear {
            startDate = Date()
            scheduleHaptics()
        }
        .onDisappear { hapticsTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Can \(weekCount) logged. \(sku.name), \(sku.sizeLabel). \(streak) day streak.")
        .accessibilityAddTraits(.isModal)
    }

    // MARK: Clocks

    private func elapsed(at date: Date) -> Double {
        guard let startDate else { return 0 }
        return date.timeIntervalSince(startDate)
    }

    private func exitElapsed(at date: Date) -> Double? {
        guard let exitStart else { return nil }
        return date.timeIntervalSince(exitStart)
    }

    private func beginExit() {
        guard exitStart == nil else { return }
        exitStart = Date()
        Haptics.tick()
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 500))
            onDone()
        }
    }

    private func scheduleHaptics() {
        guard !reduceMotion else { return }
        hapticsTask = Task {
            try? await Task.sleep(for: .milliseconds(620))   // impact
            guard !Task.isCancelled else { return }
            Haptics.thump()
            try? await Task.sleep(for: .milliseconds(1280))  // odometer lands (~1.9s)
            guard !Task.isCancelled else { return }
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(400))   // flame pop (~2.3s)
            guard !Task.isCancelled else { return }
            Haptics.tick()
        }
    }

    // MARK: Easings (the prototype's)

    private func c01(_ x: Double) -> Double { min(max(x, 0), 1) }
    private func easeOutCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private func easeInCubic(_ x: Double) -> Double { x * x * x }

    // MARK: One frame

    /// Every animated quantity for one instant, computed with the prototype's
    /// exact formulas. Plain data so the ViewBuilder below stays declarative.
    private struct FrameValues {
        var floodScale = 0.0, floodGlowOp = 0.0, celebOp = 1.0
        var canY = -940.0, canRot = 0.0, canSX = 1.0, canSY = 1.0, shakeX = 0.0
        var ringOn = false, bubblesOn = false
        var titleOp = 0.0, titleScale = 1.4
        var subOp = 0.0, subY = 14.0, lineOp = 0.0, lineY = 14.0
        var pillOp = 0.0, pillY = -64.0, roll = 0.0
        var flameOp = 0.0, flameScale = 0.3
        var contOp = 0.0, contY = 110.0
    }

    private func values(rawT: Double, exit: Double?) -> FrameValues {
        var v = FrameValues()
        let exiting = exit != nil
        let et = exit ?? 0
        // During exit the celebration holds its settled pose (prototype ct = 3.4).
        let ct = exiting ? 3.4 : rawT

        // ---- flood ----
        v.floodScale = exiting
            ? 42.0 * (1 - easeInCubic(c01(et / 0.45)))
            : 42.0 * easeOutCubic(c01(rawT / 0.4))
        v.floodGlowOp = exiting ? 1 - c01(et / 0.18) : c01((rawT - 0.28) / 0.18)
        v.celebOp = exiting ? 1 - c01(et / 0.25) : 1.0

        // ---- can drop (prototype formulas, verbatim) ----
        if ct >= 0.4 {
            if ct < 0.62 {
                let p = (ct - 0.4) / 0.22
                v.canY = -940 + 984 * p * p
            } else {
                let tau = ct - 0.62
                v.canY = 44 * exp(-5 * tau) * cos(14 * tau)
                v.canSY = 1 - 0.07 * exp(-6 * tau) * cos(14 * tau)
                v.canSX = 1 + 0.06 * exp(-6 * tau) * cos(14 * tau)
                if tau < 0.5 { v.shakeX = 2.4 * exp(-9 * tau) * sin(45 * tau) }
                v.ringOn = true
                v.bubblesOn = true
                let sway = c01((ct - 1.3) / 0.7)
                v.canRot = sway * 3 * sin((ct - 1.3) * 1.45)
                v.canY += sway * 7 * sin((ct - 1.3) * 2.1)
            }
        }

        // ---- title / sub / line ----
        let tt = ct - 1.0
        v.titleOp = tt < 0 ? 0 : c01(tt / 0.12)
        v.titleScale = tt < 0 ? 1.4 : 1 + 0.42 * exp(-5.5 * tt) * cos(7.5 * tt)
        let st = ct - 1.25
        v.subOp = st < 0 ? 0 : c01(st / 0.3)
        v.subY = (1 - v.subOp) * 14
        let lt = ct - 1.45
        v.lineOp = lt < 0 ? 0 : c01(lt / 0.3)
        v.lineY = (1 - v.lineOp) * 14

        // ---- pill / odometer / flame ----
        let pt = ct - 1.6
        v.pillOp = pt < 0 ? 0 : c01(pt / 0.12)
        v.pillY = pt < 0 ? -64.0 : -64 * exp(-5.5 * pt) * cos(7 * pt)
        let rt = ct - 1.75
        v.roll = rt < 0 ? 0 : 1 - exp(-7 * rt) * cos(9 * rt)
        let ft = ct - 2.3
        v.flameOp = ft < 0 ? 0 : c01(ft / 0.1)
        v.flameScale = ft < 0 ? 0.3 : max(0, 1 - 0.7 * exp(-7 * ft) * cos(9 * ft))

        // ---- continue ----
        let kt = ct - 2.5
        v.contOp = kt < 0 ? 0 : c01(kt / 0.15)
        v.contY = kt < 0 ? 110.0 : 110 * exp(-5 * kt) * cos(6.2 * kt)

        return v
    }

    @ViewBuilder
    private func frame(t rawT: Double, exit: Double?, size: CGSize) -> some View {
        let xu = size.width / 393.0
        let yu = size.height / 852.0
        let exiting = exit != nil
        let ct = exiting ? 3.4 : rawT
        let v = values(rawT: rawT, exit: exit)
        let floodScale = v.floodScale
        let floodGlowOp = v.floodGlowOp
        let celebOp = v.celebOp
        let canY = v.canY
        let canRot = v.canRot
        let canSX = v.canSX
        let canSY = v.canSY
        let shakeX = v.shakeX
        let ringOn = v.ringOn
        let bubblesOn = v.bubblesOn
        let titleOp = v.titleOp
        let titleScale = v.titleScale
        let subOp = v.subOp
        let subY = v.subY
        let lineOp = v.lineOp
        let lineY = v.lineY
        let pillOp = v.pillOp
        let pillY = v.pillY
        let roll = v.roll
        let flameOp = v.flameOp
        let flameScale = v.flameScale
        let contOp = v.contOp
        let contY = v.contY

        ZStack {
            // Flood circle from the confirm position (bottom center)
            Circle()
                .fill(palette.flood)
                .frame(width: 40, height: 40)
                .scaleEffect(floodScale)
                .position(x: 196.5 * xu, y: 783 * yu)

            // Stage lighting: brighter center-top, deep edges
            EllipticalGradient(
                stops: [
                    .init(color: palette.bright, location: 0),
                    .init(color: palette.flood, location: 0.45),
                    .init(color: palette.deep, location: 1),
                ],
                center: UnitPoint(x: 0.5, y: 0.36),
                startRadiusFraction: 0,
                endRadiusFraction: 1.1
            )
            .opacity(floodGlowOp)

            // Celebration content (shaken as one)
            ZStack {
                if bubblesOn {
                    CarbonationBubbles(t: ct)
                        .frame(width: 200 * xu, height: 430 * yu)
                        .position(x: 196 * xu, y: 395 * yu)
                }

                ConfettiCanvas(burst: ct - 2.05, palette: palette, xu: xu, yu: yu)

                if ringOn, ct - 0.62 < 0.7 {
                    let rp = c01((ct - 0.62) / 0.7)
                    Ellipse()
                        .strokeBorder(.white.opacity(0.65 * (1 - rp)), lineWidth: 2)
                        .frame(width: 220 * xu, height: 64 * yu)
                        .scaleEffect(0.25 + 2.15 * easeOutCubic(rp))
                        .position(x: 196 * xu, y: 632 * yu)
                }

                // THE CAN — 200×440 design frame, anchored at its base
                DesignCan(palette: palette, sheenPhase: sheenPhase(for: ct))
                    .frame(width: 200 * xu, height: 440 * yu)
                    .scaleEffect(x: canSX, y: canSY, anchor: .bottom)
                    .rotationEffect(.degrees(canRot), anchor: .bottom)
                    .position(x: 196.5 * xu, y: (168 + 220) * yu)
                    .offset(y: canY * yu)
                    .shadow(color: .black.opacity(0.4), radius: 30 * yu, y: 24 * yu)

                // CAN #N
                Text("CAN #\(weekCount)")
                    .font(.system(size: 62 * min(xu, 1.2), weight: .black, design: .rounded))
                    .kerning(-1.5)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
                    .scaleEffect(titleScale)
                    .opacity(titleOp)
                    .position(x: size.width / 2, y: 110 * yu)
                    .accessibilityHidden(true)

                // SKU line
                Text(subText)
                    .font(Theme.label(12))
                    .kerning(2.6)
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(subOp)
                    .position(x: size.width / 2, y: 630 * yu)
                    .offset(y: subY)

                // The dry one-liner
                Text(Copy.todayLine(count: todayCount))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .italic()
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(lineOp)
                    .position(x: size.width / 2, y: 658 * yu)
                    .offset(y: lineY)

                // Odometer pill + streak flame
                HStack(spacing: 10) {
                    HStack(spacing: 9) {
                        OdometerNumber(from: max(0, weekCount - 1), to: weekCount, roll: roll)
                        Text("THIS WEEK")
                            .font(Theme.label(10))
                            .kerning(2)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.12), in: .capsule)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                    .opacity(pillOp)
                    .offset(y: pillY)

                    if streak > 0 {
                        HStack(spacing: 5) {
                            Text("🔥")
                                .font(.system(size: 14))
                                .scaleEffect(flameFlicker(at: ct))
                            Text("\(streak)")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(Theme.bullRed.opacity(0.28), in: .capsule)
                        .overlay(Capsule().strokeBorder(Color(hex: "#FF7896").opacity(0.4), lineWidth: 1))
                        .opacity(flameOp)
                        .scaleEffect(flameScale)
                    }
                }
                .position(x: size.width / 2, y: 712 * yu)

                // PR / badge garnish, riding the flame beat
                if result.isPersonalRecord || !result.newBadges.isEmpty {
                    Text(result.isPersonalRecord ? Copy.newPR : "Badge unlocked: \(result.newBadges.first?.title ?? "")")
                        .font(Theme.label(11))
                        .kerning(1.5)
                        .foregroundStyle(Theme.energyYellow)
                        .opacity(flameOp)
                        .position(x: size.width / 2, y: 748 * yu)
                }

                // KEEP IT COLD
                Button(action: beginExit) {
                    Text("KEEP IT COLD")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .kerning(2.5)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.glass)
                .padding(.horizontal, 24)
                .opacity(contOp)
                .offset(y: contY)
                .position(x: size.width / 2, y: size.height - 58)
                .accessibilityLabel("Done. Keep it cold.")
            }
            .opacity(celebOp)
            .offset(x: shakeX)
        }
        .background(exiting || floodScale < 20 ? Color.clear : palette.deep)
    }

    private var subText: String {
        let short = sku.name.replacingOccurrences(of: "Red Bull ", with: "")
        return "\(short) · \(sku.sizeLabel) · \(sku.caffeineMG)mg".uppercased()
    }

    /// The idle glint keeps sweeping while the can is on stage.
    private func sheenPhase(for ct: Double) -> Double {
        ((ct - 0.62).truncatingRemainder(dividingBy: 5.5) + 5.5)
            .truncatingRemainder(dividingBy: 5.5) / 5.5
    }

    /// ccFlick: scale 1 → 1.18 on a 1.1s loop.
    private func flameFlicker(at ct: Double) -> Double {
        let p = (ct.truncatingRemainder(dividingBy: 1.1)) / 1.1
        return 1 + 0.18 * (0.5 - 0.5 * cos(2 * .pi * p))
    }

    // MARK: Reduce Motion

    /// The same information, no theatrics: flood as a plain backdrop, the can
    /// standing still, everything visible, crossfaded in by the presenter.
    private var reducedMotionBody: some View {
        GeometryReader { geo in
            ZStack {
                EllipticalGradient(
                    stops: [
                        .init(color: palette.bright, location: 0),
                        .init(color: palette.flood, location: 0.45),
                        .init(color: palette.deep, location: 1),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.36),
                    startRadiusFraction: 0,
                    endRadiusFraction: 1.1
                )
                VStack(spacing: 18) {
                    Text("CAN #\(weekCount)")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    DesignCan(palette: palette, sheenPhase: nil)
                        .frame(width: geo.size.width * 0.42, height: geo.size.width * 0.42 * 2.2)
                    Text(subText)
                        .font(Theme.label(12))
                        .kerning(2.6)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(Copy.todayLine(count: todayCount))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    if streak > 0 {
                        Text("🔥 \(streak) day streak")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Button(action: beginExit) {
                        Text("KEEP IT COLD")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .kerning(2.5)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(.glass)
                    .padding(.horizontal, 24)
                    .accessibilityLabel("Done. Keep it cold.")
                }
                .padding(.top, 40)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(3.5))
            beginExit()
        }
    }
}

// MARK: - Odometer

/// Rolling odometer digits: each column shows previous/current/next stacked
/// vertically in a 24pt window, translated up by `roll` — straight from the
/// prototype's odoDigits math.
private struct OdometerNumber: View {
    let from: Int
    let to: Int
    let roll: Double

    var body: some View {
        let fromDigits = Array(String(from).leftPadded(to: String(to).count))
        let toDigits = Array(String(to))
        HStack(spacing: 0) {
            ForEach(toDigits.indices, id: \.self) { index in
                let a = String(fromDigits[index])
                let b = String(toDigits[index])
                let r = a == b ? 0.0 : roll
                let nextDigit = ((Int(b) ?? 0) + 1) % 10
                VStack(spacing: 0) {
                    digitText(a)
                    digitText(b)
                    digitText(String(nextDigit))
                }
                // Rows sit at −24/0/+24 around the window center: +24 shows
                // row `a`, 0 shows row `b` — roll slides between them.
                .offset(y: 24 * (1 - r))
                .frame(width: 14, height: 24)
                .clipped()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(to) this week")
    }

    private func digitText(_ digit: String) -> some View {
        Text(digit)
            .font(.system(size: 21, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(height: 24)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}

// MARK: - Carbonation bubbles

/// Eight rising bubble rings on staggered loops (ccBubble).
private struct CarbonationBubbles: View {
    let t: Double

    // (x, size, duration, phase-delay) — the prototype's eight bubbles.
    private static let bubbles: [(x: CGFloat, s: CGFloat, dur: Double, delay: Double)] = [
        (18, 7, 3.1, 0.4), (52, 11, 3.8, 1.6), (88, 6, 2.6, 0.9), (120, 9, 3.4, 2.2),
        (152, 13, 4.2, 0.2), (176, 7, 2.9, 1.3), (34, 5, 2.4, 1.9), (104, 8, 3.6, 2.8),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(Self.bubbles.indices, id: \.self) { index in
                let bubble = Self.bubbles[index]
                let progress = ((t + bubble.delay).truncatingRemainder(dividingBy: bubble.dur)) / bubble.dur
                let opacity = progress < 0.12 ? progress / 0.12 * 0.75 : 0.75 * (1 - (progress - 0.12) / 0.88)
                Circle()
                    .strokeBorder(.white.opacity(opacity), lineWidth: 1.5)
                    .frame(width: bubble.s, height: bubble.s)
                    .scaleEffect(0.5 + 0.65 * progress)
                    .position(x: bubble.x, y: geo.size.height - 8)
                    .offset(y: -400 * progress)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Confetti

/// The prototype's 78 confetti particles, reproduced exactly: mulberry32
/// seeded with 42, initial angle −π/2 ± 1, speed 240–670, 420·t² gravity,
/// ±760°/s spin, 25% can-shaped (silver lid over color). Yellow, silver, and
/// two flavor tints.
private struct ConfettiCanvas: View {
    let burst: Double
    let palette: CanPalette
    let xu: CGFloat
    let yu: CGFloat

    private struct Particle {
        let vx: Double, vy: Double
        let w: Double, h: Double
        let isCan: Bool
        let colorIndex: Int
        let spin: Double, drift: Double, rotation0: Double
    }

    private static let particles: [Particle] = {
        var random = Mulberry32(seed: 42)
        var particles: [Particle] = []
        for _ in 0..<78 {
            let angle = -Double.pi / 2 + (random.next() - 0.5) * 2.0
            let speed = 240 + random.next() * 430
            let isCan = random.next() < 0.25
            particles.append(Particle(
                vx: cos(angle) * speed * (0.6 + random.next() * 0.5),
                vy: sin(angle) * speed,
                w: isCan ? 7 : 5 + random.next() * 6,
                h: isCan ? 12 : 6 + random.next() * 9,
                isCan: isCan,
                colorIndex: Int(random.next() * 5) % 5,
                spin: (random.next() - 0.5) * 760,
                drift: (random.next() - 0.5) * 70,
                rotation0: random.next() * 360
            ))
        }
        return particles
    }()

    var body: some View {
        Canvas { context, _ in
            guard burst > 0, burst < 2.1 else { return }
            let colors: [Color] = [
                Theme.energyYellow, Theme.energyYellow, Theme.silver,
                palette.bright, palette.stripe,
            ]
            let cx = 196.0 * xu, cy = 430.0 * yu
            for particle in Self.particles {
                let x = cx + (particle.vx * burst + particle.drift * burst * burst) * xu
                let y = cy + (particle.vy * burst + 420 * burst * burst) * yu
                let rotation = Angle.degrees(particle.rotation0 + particle.spin * burst)
                let opacity = burst < 1.4 ? 1.0 : max(0, 1 - (burst - 1.4) / 0.7)

                var inner = context
                inner.opacity = opacity
                inner.translateBy(x: x, y: y)
                inner.rotate(by: rotation)

                let rect = CGRect(x: -particle.w / 2, y: -particle.h / 2, width: particle.w, height: particle.h)
                let path = Path(roundedRect: rect, cornerRadius: particle.isCan ? 3 : 1.5)
                if particle.isCan {
                    // Tiny can: silver lid over a flavor body.
                    inner.fill(path, with: .color(colors[particle.colorIndex]))
                    let lid = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.22)
                    inner.fill(Path(lid), with: .color(Color(hex: "#e8ecf0")))
                } else {
                    inner.fill(path, with: .color(colors[particle.colorIndex]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Deterministic PRNG matching the prototype's mulberry32 — same seed, same
/// confetti, every single time. That's the point.
private struct Mulberry32 {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func next() -> Double {
        state = state &+ 0x6D2B79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}
