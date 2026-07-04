import UIKit

/// The app's haptic vocabulary.
/// tick = light UI interactions (tab changes, selections),
/// thump = a scan locking on, success/warning = notification-grade moments.
@MainActor
enum Haptics {

    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func thump() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1.0)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
