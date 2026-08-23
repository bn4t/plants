import Observation
import SwiftData
import SwiftUI
import UIKit

enum PlantsSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Plant.self, CareEvent.self]
    }
}

enum PlantsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [PlantsSchemaV1.self, PlantsSchemaV1_5.self, PlantsSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: PlantsSchemaV1.self, toVersion: PlantsSchemaV1_5.self),
            .lightweight(fromVersion: PlantsSchemaV1_5.self, toVersion: PlantsSchemaV2.self)
        ]
    }
}

@MainActor
@Observable
final class PlantStoreController {
    private(set) var container: ModelContainer?
    private(set) var errorMessage: String?
    private(set) var storeURL: URL?

    init() {
        load()
    }

    func load() {
        let schema = Schema(versionedSchema: PlantsSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        storeURL = configuration.url
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: PlantsMigrationPlan.self,
                configurations: [configuration]
            )
            errorMessage = nil
        } catch {
            container = nil
            errorMessage = error.localizedDescription
        }
    }

    func resetLocalData() throws {
        guard let storeURL else { return }
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        load()
    }
}

@main
struct PlantsApp: App {
    @State private var settings: AppSettings
    @State private var store: PlantStoreController

    init() {
        let settings = AppSettings()
        let store = PlantStoreController()
        _settings = State(initialValue: settings)
        _store = State(initialValue: store)
        if let container = store.container {
            NotificationService.shared.configureAtLaunch(modelContainer: container)
        }
    }

    var body: some Scene {
        WindowGroup {
            StoreHostView(store: store)
                .environment(settings)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(BotanicalTheme.tint)
        }
    }
}

private struct StoreHostView: View {
    let store: PlantStoreController

    var body: some View {
        Group {
            if let container = store.container {
                AppShellView()
                    .modelContainer(container)
                    .task {
                        await AppBootstrapper.prepare(container: container)
                    }
            } else {
                StoreRecoveryView(store: store)
            }
        }
    }
}

private struct StoreRecoveryView: View {
    let store: PlantStoreController
    @State private var showingResetConfirmation = false
    @State private var resetError: String?

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Plants could not open", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Your plant data has not been deleted. Retry opening it, or reset local data if you no longer need it.")
            } actions: {
                Button("Retry") { store.load() }
                    .buttonStyle(.borderedProminent)
                Button("Reset local data", role: .destructive) {
                    showingResetConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            .navigationTitle("Data recovery")
            .alert("Reset all local plant data?", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) {
                    do {
                        try store.resetLocalData()
                    } catch {
                        resetError = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the local plant library and care history.")
            }
            .alert("Could not reset data", isPresented: Binding(
                get: { resetError != nil },
                set: { if !$0 { resetError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resetError ?? "")
            }
        }
    }
}

@MainActor
enum AppBootstrapper {
    static func prepare(container: ModelContainer) async {
        _ = Secrets.openRouterAPIKey
        let context = ModelContext(container)
        guard let plants = try? context.fetch(FetchDescriptor<Plant>()) else { return }
        let settings = AppSettings().snapshot
        var changed = false

        for plant in plants {
            if [plant.wateringIntervalSpring, plant.wateringIntervalSummer,
                plant.wateringIntervalAutumn, plant.wateringIntervalWinter].contains(where: { $0 <= 0 }) {
                plant.seasonalWatering = SeasonalWatering.derived(from: plant.wateringIntervalDays)
                changed = true
            }
            if plant.nextCareCheckDate == nil {
                let recommendation = CareRecommendationEngine.recommendation(
                    for: plant.careInput(),
                    hemisphere: settings.hemisphere
                )
                plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                    addingDays: plant.lastWatered == nil ? 0 : recommendation.predictedIntervalDays,
                    to: plant.lastWatered ?? .now,
                    hour: settings.reminderHour,
                    minute: settings.reminderMinute
                )
                changed = true
            }
        }
        if changed { try? context.save() }

        let shouldSeed = CommandLine.arguments.contains("--seed-demo")
            || UserDefaults.standard.bool(forKey: "seedDemo")
        if shouldSeed {
            seedDemoIfEmpty(context: context, settings: settings)
            UserDefaults.standard.removeObject(forKey: "seedDemo")
        }

        let refreshedPlants = (try? context.fetch(FetchDescriptor<Plant>())) ?? []
        await NotificationService.shared.rescheduleAll(for: refreshedPlants, settings: settings)
    }

    private static func seedDemoIfEmpty(
        context: ModelContext,
        settings: AppSettingsSnapshot
    ) {
        let existing = (try? context.fetch(FetchDescriptor<Plant>())) ?? []
        guard existing.isEmpty else { return }

        let sampleData = try? Data(contentsOf: URL(fileURLWithPath: "/Users/ben/code/plant-app/sample-plant.jpg"))
        let processed = sampleData.flatMap { data in
            UIImage(data: data).flatMap(PhotoProcessor.process)
        }
        let now = Date()
        let calendar = Calendar.current
        let fixtures: [(String, String, SeasonalWatering, String, String)] = [
            ("Monstera Deliciosa", "Monstera deliciosa", .init(spring: 9, summer: 8, autumn: 12, winter: 16), "Water when the top 2–3 cm are dry", "Use a balanced feed while actively growing"),
            ("Snake Plant", "Dracaena trifasciata", .init(spring: 18, summer: 14, autumn: 22, winter: 30), "Water when most of the potting mix is dry", "Feed sparingly during active growth"),
            ("Pothos", "Epipremnum aureum", .init(spring: 8, summer: 7, autumn: 11, winter: 15), "Water when the top 3 cm are dry", "Use a balanced feed while actively growing"),
            ("Fiddle Leaf Fig", "Ficus lyrata", .init(spring: 10, summer: 9, autumn: 14, winter: 20), "Water when the top 3–4 cm are dry", "Follow the product label during active growth")
        ]

        for (index, fixture) in fixtures.enumerated() {
            let plant = Plant(
                commonName: fixture.0,
                scientificName: fixture.1,
                photo: index == 0 ? processed : nil,
                wateringIntervalDays: fixture.2.summer,
                wateringTrigger: fixture.3,
                fertilizingIntervalDays: 30,
                fertilizingNotes: fixture.4,
                lightRequirement: index == 1 ? "low" : "bright_indirect",
                toxicityNote: "Keep away from pets if ingested",
                careNote: index == 0 ? "Wipe broad leaves and provide climbing support" : "",
                seasonalWatering: fixture.2,
                identificationConfidence: "high"
            )
            let lastWatered = calendar.date(byAdding: .day, value: [-10, -2, 0, -5][index], to: now) ?? now
            plant.lastWatered = lastWatered
            plant.lastFertilized = calendar.date(byAdding: .day, value: -40, to: now)
            plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                addingDays: fixture.2.interval(
                    for: Season.current(for: now, hemisphere: settings.hemisphere)
                ),
                to: lastWatered,
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
            context.insert(plant)
            context.insert(CareEvent(kind: .watering, date: lastWatered, plant: plant))
        }
        try? context.save()
    }
}
