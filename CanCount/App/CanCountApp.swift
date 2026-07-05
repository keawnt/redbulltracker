import SwiftUI
import SwiftData
import UserNotifications

@main
struct CanCountApp: App {
    let container: ModelContainer

    /// Shared handle for background notification actions (NotificationRouter
    /// logs "my usual" without the UI ever appearing).
    static var sharedContainer: ModelContainer?

    init() {
        do {
            container = try ModelContainer(
                for: SKU.self, CanLog.self, UserProfile.self, Crew.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        Self.sharedContainer = container
        SeedLoader.seedIfNeeded(container: container)

        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        StoreRadarService.registerNotificationCategory()
        StoreRadarService.shared.resumeIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
