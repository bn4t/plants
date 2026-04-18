import SwiftData
import SwiftUI

@main
struct PlantsApp: App {
    private let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Plant.self, CareEvent.self)
        } catch {
            fatalError("Failed to create model container: \(error.localizedDescription)")
        }
    }()

    init() {
        NotificationService.shared.configureAtLaunch(modelContainer: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            PlantListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
