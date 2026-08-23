import Foundation
import SwiftData

// This schema mirrors the first committed app release. Keep it stable so stores
// created by that release can always be exercised by the migration tests.
enum PlantsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Plant.self, CareEvent.self]
    }

    @Model
    final class Plant {
        @Attribute(.unique) var id: UUID
        var commonName: String
        var scientificName: String
        var createdAt: Date
        @Attribute(.externalStorage) var photo: Data?

        @Relationship(deleteRule: .cascade, inverse: \CareEvent.plant)
        var events: [CareEvent] = []

        var wateringIntervalDays: Int
        var lastWatered: Date?
        var wateringTrigger: String
        var fertilizingIntervalDays: Int
        var lastFertilized: Date?
        var fertilizingNotes: String
        var lightRequirement: String
        var toxicityNote: String
        var careNote: String

        init(
            id: UUID = UUID(),
            commonName: String,
            scientificName: String,
            photo: Data? = nil,
            wateringIntervalDays: Int,
            wateringTrigger: String,
            fertilizingIntervalDays: Int,
            fertilizingNotes: String,
            lightRequirement: String,
            toxicityNote: String,
            careNote: String,
            createdAt: Date = .now
        ) {
            self.id = id
            self.commonName = commonName
            self.scientificName = scientificName
            self.createdAt = createdAt
            self.photo = photo
            self.wateringIntervalDays = wateringIntervalDays
            self.lastWatered = nil
            self.wateringTrigger = wateringTrigger
            self.fertilizingIntervalDays = fertilizingIntervalDays
            self.lastFertilized = nil
            self.fertilizingNotes = fertilizingNotes
            self.lightRequirement = lightRequirement
            self.toxicityNote = toxicityNote
            self.careNote = careNote
        }
    }

    @Model
    final class CareEvent {
        @Attribute(.unique) var id: UUID
        var kind: String
        var date: Date
        var plant: Plant?

        init(id: UUID = UUID(), kind: String, date: Date = .now, plant: Plant? = nil) {
            self.id = id
            self.kind = kind
            self.date = date
            self.plant = plant
        }
    }
}

// A development build added seasonal values before the adaptive-care release.
// Keeping its schema allows those local stores to migrate without losing them.
enum PlantsSchemaV1_5: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 5, 0)

    static var models: [any PersistentModel.Type] {
        [Plant.self, CareEvent.self]
    }

    @Model
    final class Plant {
        @Attribute(.unique) var id: UUID
        var commonName: String
        var scientificName: String
        var createdAt: Date
        @Attribute(.externalStorage) var photo: Data?

        @Relationship(deleteRule: .cascade, inverse: \CareEvent.plant)
        var events: [CareEvent] = []

        var wateringIntervalDays: Int
        var lastWatered: Date?
        var wateringTrigger: String
        var fertilizingIntervalDays: Int
        var lastFertilized: Date?
        var fertilizingNotes: String
        var lightRequirement: String
        var toxicityNote: String
        var careNote: String
        var wateringIntervalSpring: Int = 7
        var wateringIntervalSummer: Int = 7
        var wateringIntervalAutumn: Int = 7
        var wateringIntervalWinter: Int = 7
        var fertilizingPausedInWinter: Bool = true
        var seasonalCareNote: String = ""

        init(
            id: UUID = UUID(),
            commonName: String,
            scientificName: String,
            wateringIntervalDays: Int,
            fertilizingIntervalDays: Int,
            createdAt: Date = .now
        ) {
            self.id = id
            self.commonName = commonName
            self.scientificName = scientificName
            self.createdAt = createdAt
            self.photo = nil
            self.wateringIntervalDays = wateringIntervalDays
            self.lastWatered = nil
            self.wateringTrigger = ""
            self.fertilizingIntervalDays = fertilizingIntervalDays
            self.lastFertilized = nil
            self.fertilizingNotes = ""
            self.lightRequirement = "medium"
            self.toxicityNote = ""
            self.careNote = ""
        }
    }

    @Model
    final class CareEvent {
        @Attribute(.unique) var id: UUID
        var kind: String
        var date: Date
        var plant: Plant?

        init(id: UUID = UUID(), kind: String, date: Date = .now, plant: Plant? = nil) {
            self.id = id
            self.kind = kind
            self.date = date
            self.plant = plant
        }
    }
}
