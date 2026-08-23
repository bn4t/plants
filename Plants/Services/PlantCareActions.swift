import Foundation
import SwiftData
import UIKit

struct CareActionReceipt: Identifiable, Sendable {
    let id = UUID()
    let plantID: UUID
    let insertedEventIDs: [UUID]
    let previousLastWatered: Date?
    let previousLastFertilized: Date?
    let previousNextCareCheckDate: Date?
    let previousGrowthState: GrowthState
    let message: String
}

@MainActor
enum PlantCareActions {
    static func apply(
        _ outcome: CareCheckOutcome,
        to plant: Plant,
        includeFertilizer: Bool = false,
        confirmedGrowthState: GrowthState? = nil,
        settings: AppSettingsSnapshot,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> CareActionReceipt {
        let previousLastWatered = plant.lastWatered
        let previousLastFertilized = plant.lastFertilized
        let previousNextCareCheckDate = plant.nextCareCheckDate
        let previousGrowthState = plant.growthState
        if let confirmedGrowthState {
            plant.growthState = confirmedGrowthState
        }

        let recommendation = CareRecommendationEngine.recommendation(
            for: plant.careInput(),
            hemisphere: settings.hemisphere,
            calendar: calendar,
            now: now
        )
        var insertedEvents: [CareEvent] = []
        let message: String

        switch outcome {
        case .dryAndWatered:
            plant.lastWatered = now
            let watering = CareEvent(kind: .watering, date: now, plant: plant)
            context.insert(watering)
            insertedEvents.append(watering)
            plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                addingDays: recommendation.predictedIntervalDays,
                to: now,
                hour: settings.reminderHour,
                minute: settings.reminderMinute,
                calendar: calendar
            )

            if includeFertilizer,
               recommendation.fertilizerDue,
               CareRecommendationEngine.isFertilizerActive(
                   growthState: plant.growthState,
                   season: recommendation.season
               ) {
                plant.lastFertilized = now
                let fertilizing = CareEvent(kind: .fertilizing, date: now, plant: plant)
                context.insert(fertilizing)
                insertedEvents.append(fertilizing)
                message = "Watering and feeding logged"
            } else {
                message = "Watering logged"
            }

        case .stillDamp:
            let damp = CareEvent(kind: .soilCheckDamp, date: now, plant: plant)
            context.insert(damp)
            insertedEvents.append(damp)
            plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                addingDays: CareRecommendationEngine.dampRecheckDays(
                    predictedIntervalDays: recommendation.predictedIntervalDays
                ),
                to: now,
                hour: settings.reminderHour,
                minute: settings.reminderMinute,
                calendar: calendar
            )
            message = "Still damp, check moved"

        case .remindTomorrow:
            plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                addingDays: 1,
                to: now,
                hour: settings.reminderHour,
                minute: settings.reminderMinute,
                calendar: calendar
            )
            message = "Check moved to tomorrow"
        }

        try context.save()
        await NotificationService.shared.scheduleSoilCheck(
            for: plant,
            settings: settings,
            now: now
        )
        if settings.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        return CareActionReceipt(
            plantID: plant.id,
            insertedEventIDs: insertedEvents.map(\.id),
            previousLastWatered: previousLastWatered,
            previousLastFertilized: previousLastFertilized,
            previousNextCareCheckDate: previousNextCareCheckDate,
            previousGrowthState: previousGrowthState,
            message: message
        )
    }

    static func logCare(
        kind: CareEventKind,
        for plant: Plant,
        date: Date,
        soilWasMoist: Bool,
        settings: AppSettingsSnapshot,
        context: ModelContext,
        calendar: Calendar = .current
    ) async throws -> CareActionReceipt {
        if kind == .fertilizing && !soilWasMoist {
            throw CareActionError.fertilizerRequiresMoistSoil
        }

        let previousLastWatered = plant.lastWatered
        let previousLastFertilized = plant.lastFertilized
        let previousNextCareCheckDate = plant.nextCareCheckDate
        let previousGrowthState = plant.growthState
        let event = CareEvent(kind: kind, date: date, plant: plant)
        context.insert(event)

        switch kind {
        case .watering:
            plant.lastWatered = date
            let recommendation = CareRecommendationEngine.recommendation(
                for: plant.careInput(),
                hemisphere: settings.hemisphere,
                calendar: calendar,
                now: date
            )
            plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                addingDays: recommendation.predictedIntervalDays,
                to: date,
                hour: settings.reminderHour,
                minute: settings.reminderMinute,
                calendar: calendar
            )
        case .fertilizing:
            plant.lastFertilized = date
        case .soilCheckDamp:
            plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                addingDays: 1,
                to: date,
                hour: settings.reminderHour,
                minute: settings.reminderMinute,
                calendar: calendar
            )
        }

        try context.save()
        await NotificationService.shared.scheduleSoilCheck(for: plant, settings: settings)
        if settings.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        return CareActionReceipt(
            plantID: plant.id,
            insertedEventIDs: [event.id],
            previousLastWatered: previousLastWatered,
            previousLastFertilized: previousLastFertilized,
            previousNextCareCheckDate: previousNextCareCheckDate,
            previousGrowthState: previousGrowthState,
            message: kind == .fertilizing ? "Feeding logged" : "Care logged"
        )
    }

    static func undo(
        _ receipt: CareActionReceipt,
        plant: Plant,
        settings: AppSettingsSnapshot,
        context: ModelContext
    ) async throws {
        guard plant.id == receipt.plantID else { return }
        for event in plant.events where receipt.insertedEventIDs.contains(event.id) {
            context.delete(event)
        }
        plant.lastWatered = receipt.previousLastWatered
        plant.lastFertilized = receipt.previousLastFertilized
        plant.nextCareCheckDate = receipt.previousNextCareCheckDate
        plant.growthState = receipt.previousGrowthState
        try context.save()
        await NotificationService.shared.scheduleSoilCheck(for: plant, settings: settings)
    }
}

enum CareActionError: LocalizedError {
    case fertilizerRequiresMoistSoil

    var errorDescription: String? {
        switch self {
        case .fertilizerRequiresMoistSoil:
            "Water first or confirm that the potting mix is already moist before feeding."
        }
    }
}
