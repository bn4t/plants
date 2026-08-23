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

    // Kept for compatibility with the first shipped schema.
    var wateringIntervalDays: Int
    var lastWatered: Date?
    var wateringTrigger: String

    var fertilizingIntervalDays: Int
    var lastFertilized: Date?
    var fertilizingNotes: String

    var lightRequirement: String
    var toxicityNote: String
    var careNote: String

    // Species-level starting points. Observed watering cycles supersede these.
    var wateringIntervalSpring: Int = 7
    var wateringIntervalSummer: Int = 7
    var wateringIntervalAutumn: Int = 7
    var wateringIntervalWinter: Int = 7

    // Kept so stores produced by the in-progress seasonal redesign remain readable.
    var fertilizingPausedInWinter: Bool = true
    var seasonalCareNote: String = ""

    var nextCareCheckDate: Date?
    var growthStateRaw: String = GrowthState.automatic.rawValue
    var identificationConfidence: String = "unknown"

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
        careNote: String = "",
        seasonalWatering: SeasonalWatering? = nil,
        fertilizingPausedInWinter: Bool = true,
        seasonalCareNote: String = "",
        nextCareCheckDate: Date? = nil,
        growthState: GrowthState = .automatic,
        identificationConfidence: String = "unknown",
        createdAt: Date = .now
    ) {
        self.id = id
        self.commonName = commonName
        self.scientificName = scientificName
        self.createdAt = createdAt
        self.photo = photo
        self.wateringIntervalDays = wateringIntervalDays.clamped(to: 1...60)
        self.lastWatered = nil
        self.wateringTrigger = wateringTrigger
        self.fertilizingIntervalDays = fertilizingIntervalDays.clamped(to: 0...120)
        self.lastFertilized = nil
        self.fertilizingNotes = fertilizingNotes
        self.lightRequirement = lightRequirement
        self.toxicityNote = toxicityNote
        self.careNote = careNote

        let seasonal = seasonalWatering ?? SeasonalWatering.derived(from: wateringIntervalDays)
        self.wateringIntervalSpring = seasonal.spring.clamped(to: 1...60)
        self.wateringIntervalSummer = seasonal.summer.clamped(to: 1...60)
        self.wateringIntervalAutumn = seasonal.autumn.clamped(to: 1...60)
        self.wateringIntervalWinter = seasonal.winter.clamped(to: 1...60)
        self.fertilizingPausedInWinter = fertilizingPausedInWinter
        self.seasonalCareNote = seasonalCareNote
        self.nextCareCheckDate = nextCareCheckDate
        self.growthStateRaw = growthState.rawValue
        self.identificationConfidence = identificationConfidence
    }

    var seasonalWatering: SeasonalWatering {
        get {
            let values = SeasonalWatering(
                spring: wateringIntervalSpring,
                summer: wateringIntervalSummer,
                autumn: wateringIntervalAutumn,
                winter: wateringIntervalWinter
            )
            if [values.spring, values.summer, values.autumn, values.winter].allSatisfy({ $0 > 0 }) {
                return values.clamped
            }
            return SeasonalWatering.derived(from: wateringIntervalDays)
        }
        set {
            let value = newValue.clamped
            wateringIntervalSpring = value.spring
            wateringIntervalSummer = value.summer
            wateringIntervalAutumn = value.autumn
            wateringIntervalWinter = value.winter
            wateringIntervalDays = value.summer
        }
    }

    var growthState: GrowthState {
        get { GrowthState(rawValue: growthStateRaw) ?? .automatic }
        set { growthStateRaw = newValue.rawValue }
    }

    var soilCheckGuidance: String {
        let trimmed = wateringTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Check the potting mix before watering" : trimmed
    }

    func careInput() -> CareRecommendationInput {
        CareRecommendationInput(
            seasonalWatering: seasonalWatering,
            events: events.compactMap { event in
                guard let kind = CareEventKind(rawValue: event.kind) else { return nil }
                return CareEventSnapshot(kind: kind, date: event.date)
            },
            lastWatered: lastWatered,
            lastFertilized: lastFertilized,
            nextCareCheckDate: nextCareCheckDate,
            fertilizingIntervalDays: fertilizingIntervalDays,
            growthState: growthState
        )
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
