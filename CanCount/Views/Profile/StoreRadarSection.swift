import SwiftUI

/// Profile card for the location nudges. Opt-in toggle, permission status,
/// and (in Debug) a test-fire button so the flow is checkable without
/// driving to a gas station.
struct StoreRadarSection: View {
    @State private var radar = StoreRadarService.shared

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MicroLabel(text: "Store radar")

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "location.viewfinder")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.racingBlue)
                            .frame(width: 34, height: 34)
                            .background(Theme.racingBlue.opacity(0.15), in: .rect(cornerRadius: 10))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Near a store? We check in.")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Gas stations, corner stores, groceries. You confess.")
                                .font(Theme.label(11))
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        Toggle("", isOn: $radar.isEnabled)
                            .labelsHidden()
                            .tint(Theme.energyYellow)
                            .accessibilityLabel("Store radar")
                    }

                    Text(radar.authorizationSummary)
                        .font(Theme.label(11))
                        .foregroundStyle(.white.opacity(0.45))

                    if radar.permissionsDenied {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open Settings")
                                .font(Theme.label(12))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.glass)
                    }

                    #if DEBUG
                    Button {
                        radar.fireTestNudge()
                        Haptics.tick()
                    } label: {
                        Label("Send test nudge (3s)", systemImage: "bell.badge")
                            .font(Theme.label(11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
