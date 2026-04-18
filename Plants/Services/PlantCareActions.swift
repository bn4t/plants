import Foundation
import SwiftData

@MainActor
enum PlantCareActions {
    static func markWatered(_ plant: Plant, context: ModelContext) async throws {
        plant.lastWatered = .now
        context.insert(CareEvent(kind: .water, plant: plant))
        try context.save()
        await NotificationService.shared.scheduleWater(for: plant)
    }

    static func markFertilized(_ plant: Plant, context: ModelContext) async throws {
        plant.lastFertilized = .now
        context.insert(CareEvent(kind: .fertilize, plant: plant))
        try context.save()
        await NotificationService.shared.scheduleFertilize(for: plant)
    }
}
