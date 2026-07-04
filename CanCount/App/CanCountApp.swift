import SwiftUI
import SwiftData

@main
struct CanCountApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: SKU.self, CanLog.self, UserProfile.self, Crew.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        SeedLoader.seedIfNeeded(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
