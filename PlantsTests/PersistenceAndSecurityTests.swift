import Security
import SwiftData
import XCTest
@testable import Plants

@MainActor
final class PersistenceAndSecurityTests: XCTestCase {
    func testLegacyDefaultsKeyMigratesToDeviceOnlyKeychain() throws {
        let suffix = UUID().uuidString
        let suiteName = "me.bn4t.plants.tests.\(suffix)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = KeychainCredentialStore(
            service: "me.bn4t.plants.tests.\(suffix)",
            account: "openrouter",
            legacyDefaultsKey: "legacy-key",
            defaults: defaults
        )
        defer {
            try? store.clear()
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set("legacy-test-token", forKey: "legacy-key")

        XCTAssertEqual(store.value(), "legacy-test-token")
        XCTAssertNil(defaults.string(forKey: "legacy-key"))

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: store.account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &result), errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    func testCommittedV1SchemaMigratesWithoutLosingPlantPhotoOrHistory() throws {
        let location = temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        try autoreleasepool {
            let schema = Schema(versionedSchema: PlantsSchemaV1.self)
            let configuration = ModelConfiguration(
                "MigrationFixture",
                schema: schema,
                url: location.store,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let legacy = PlantsSchemaV1.Plant(
                commonName: "Legacy Monstera",
                scientificName: "Monstera deliciosa",
                photo: Data([1, 2, 3, 4]),
                wateringIntervalDays: 9,
                wateringTrigger: "Top layer dry",
                fertilizingIntervalDays: 30,
                fertilizingNotes: "Follow the label",
                lightRequirement: "bright_indirect",
                toxicityNote: "Keep away from pets",
                careNote: "Provide support"
            )
            let event = PlantsSchemaV1.CareEvent(
                kind: CareEventKind.watering.rawValue,
                date: Date(timeIntervalSince1970: 100),
                plant: legacy
            )
            context.insert(legacy)
            context.insert(event)
            try context.save()
        }

        let container = try migratedContainer(at: location.store)
        let context = ModelContext(container)
        let plants = try context.fetch(FetchDescriptor<Plant>())
        let plant = try XCTUnwrap(plants.first)

        XCTAssertEqual(plants.count, 1)
        XCTAssertEqual(plant.commonName, "Legacy Monstera")
        XCTAssertEqual(plant.photo, Data([1, 2, 3, 4]))
        XCTAssertEqual(plant.events.count, 1)
        XCTAssertEqual(plant.events.first?.kind, CareEventKind.watering.rawValue)
        XCTAssertEqual(plant.seasonalWatering, .init(spring: 7, summer: 7, autumn: 7, winter: 7))
        XCTAssertEqual(plant.growthState, .automatic)
    }

    func testSeasonalDevelopmentSchemaPreservesValidSeasonValues() throws {
        let location = temporaryStoreLocation()
        defer { try? FileManager.default.removeItem(at: location.directory) }

        try autoreleasepool {
            let schema = Schema(versionedSchema: PlantsSchemaV1_5.self)
            let configuration = ModelConfiguration(
                "SeasonalMigrationFixture",
                schema: schema,
                url: location.store,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let legacy = PlantsSchemaV1_5.Plant(
                commonName: "Seasonal Plant",
                scientificName: "Planta temporalis",
                wateringIntervalDays: 8,
                fertilizingIntervalDays: 28
            )
            legacy.wateringIntervalSpring = 6
            legacy.wateringIntervalSummer = 8
            legacy.wateringIntervalAutumn = 11
            legacy.wateringIntervalWinter = 17
            legacy.seasonalCareNote = "Keep the valid seasonal note"
            context.insert(legacy)
            try context.save()
        }

        let container = try migratedContainer(at: location.store)
        let context = ModelContext(container)
        let plant = try XCTUnwrap(try context.fetch(FetchDescriptor<Plant>()).first)

        XCTAssertEqual(plant.seasonalWatering, .init(spring: 6, summer: 8, autumn: 11, winter: 17))
        XCTAssertEqual(plant.seasonalCareNote, "Keep the valid seasonal note")
    }

    private func migratedContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: PlantsSchemaV2.self)
        let configuration = ModelConfiguration(
            "MigratedFixture",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: PlantsMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func temporaryStoreLocation() -> (directory: URL, store: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PlantsMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appending(path: "Plants.store"))
    }
}
