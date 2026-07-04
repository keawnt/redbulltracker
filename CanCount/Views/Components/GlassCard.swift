import SwiftUI

/// CanCount's standard surface: a rounded Liquid Glass card floating on the
/// dark canvas, optionally tinted toward a flavor accent.
///
/// Content is inset with a comfortable default padding. Sizing is left to the
/// caller — add `.frame(maxWidth: .infinity)` (inside or outside) for
/// full-width cards.
struct GlassCard<Content: View>: View {
    private let radius: CGFloat
    private let tint: Color?
    private let content: Content

    init(
        radius: CGFloat = Theme.cardRadius,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
    }
}

#Preview("GlassCard") {
    ZStack {
        Theme.canvas.ignoresSafeArea()
        VStack(spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    MicroLabel(text: "Plain glass")
                    Text("Floating on the void")
                        .font(Theme.label(16))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GlassCard(tint: Theme.energyYellow.opacity(0.35)) {
                VStack(alignment: .leading, spacing: 6) {
                    MicroLabel(text: "Tinted glass")
                    Text("Energy yellow, obviously")
                        .font(Theme.label(16))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}
