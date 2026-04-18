import Foundation
import SwiftData

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
        wateringTrigger: String = "",
        fertilizingIntervalDays: Int,
        fertilizingNotes: String = "",
        lightRequirement: String = "medium",
        toxicityNote: String = "",
        careNote: String = ""
    ) {
        self.id = id
        self.commonName = commonName
        self.scientificName = scientificName
        self.createdAt = .now
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

    var nextWateringDate: Date? {
        guard let lastWatered else { return nil }
        return lastWatered.addingTimeInterval(TimeInterval(wateringIntervalDays) * 86_400)
    }

    var nextFertilizingDate: Date? {
        guard fertilizingIntervalDays > 0, let lastFertilized else { return nil }
        return lastFertilized.addingTimeInterval(TimeInterval(fertilizingIntervalDays) * 86_400)
    }

    var daysUntilWatering: Int? {
        guard let nextWateringDate else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: nextWateringDate).day ?? 0
    }

    var daysUntilFertilizing: Int? {
        guard let nextFertilizingDate else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: nextFertilizingDate).day ?? 0
    }

    var wateredToday: Bool {
        guard let lastWatered else { return false }
        return Calendar.current.isDateInToday(lastWatered)
    }

    var fertilizedToday: Bool {
        guard fertilizingIntervalDays > 0, let lastFertilized else { return false }
        return Calendar.current.isDateInToday(lastFertilized)
    }

    var needsInitialWatering: Bool {
        lastWatered == nil
    }

    var needsInitialFertilizing: Bool {
        fertilizingIntervalDays > 0 && lastFertilized == nil
    }
}
