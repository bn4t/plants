import SwiftData
import XCTest
@testable import Plants

@MainActor
final class PlantCareActionsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }()

    private var settings: AppSettingsSnapshot {
        AppSettingsSnapshot(
            hemisphere: .northern,
            reminderHour: 9,
            reminderMinute: 0,
            hapticsEnabled: false
        )
    }

    func testStillDampRecordsObservationAndReschedules() async throws {
        let (container, context, plant) = try makeStore()
        _ = container
        let now = date(2026, 8, 23, 14)
        plant.nextCareCheckDate = now

        _ = try await PlantCareActions.apply(
            .stillDamp,
            to: plant,
            settings: settings,
            context: context,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plant.events.count, 1)
        XCTAssertEqual(plant.events.first?.kind, CareEventKind.soilCheckDamp.rawValue)
        XCTAssertEqual(plant.nextCareCheckDate, date(2026, 8, 25, 9))
    }

    func testTomorrowDoesNotTrainCareModel() async throws {
        let (container, context, plant) = try makeStore()
        _ = container
        let now = date(2026, 8, 23, 14)

        _ = try await PlantCareActions.apply(
            .remindTomorrow,
            to: plant,
            settings: settings,
            context: context,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(plant.events.isEmpty)
        XCTAssertEqual(plant.nextCareCheckDate, date(2026, 8, 24, 9))
    }

    func testDryWateredCanLogFeedOnlyWithActiveGrowth() async throws {
        let (container, context, plant) = try makeStore()
        _ = container
        let now = date(2026, 8, 23, 14)

        _ = try await PlantCareActions.apply(
            .dryAndWatered,
            to: plant,
            includeFertilizer: true,
            confirmedGrowthState: .active,
            settings: settings,
            context: context,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(plant.growthState, .active)
        XCTAssertEqual(plant.lastWatered, now)
        XCTAssertEqual(plant.lastFertilized, now)
        XCTAssertEqual(Set(plant.events.map(\.kind)), Set([
            CareEventKind.watering.rawValue,
            CareEventKind.fertilizing.rawValue
        ]))
    }

    func testRestingPlantSuppressesFeed() async throws {
        let (container, context, plant) = try makeStore(growthState: .resting)
        _ = container
        let now = date(2026, 8, 23, 14)

        _ = try await PlantCareActions.apply(
            .dryAndWatered,
            to: plant,
            includeFertilizer: true,
            settings: settings,
            context: context,
            now: now,
            calendar: calendar
        )

        XCTAssertNil(plant.lastFertilized)
        XCTAssertEqual(plant.events.filter { $0.kind == CareEventKind.fertilizing.rawValue }.count, 0)
    }

    func testUndoRestoresDatesAndRemovesInsertedEvents() async throws {
        let (container, context, plant) = try makeStore()
        _ = container
        let previousWatering = date(2026, 8, 12)
        let previousCheck = date(2026, 8, 22, 9)
        plant.lastWatered = previousWatering
        plant.nextCareCheckDate = previousCheck
        try context.save()

        let receipt = try await PlantCareActions.apply(
            .dryAndWatered,
            to: plant,
            settings: settings,
            context: context,
            now: date(2026, 8, 23, 14),
            calendar: calendar
        )
        try await PlantCareActions.undo(
            receipt,
            plant: plant,
            settings: settings,
            context: context
        )

        XCTAssertEqual(plant.lastWatered, previousWatering)
        XCTAssertEqual(plant.nextCareCheckDate, previousCheck)
        let events = try context.fetch(FetchDescriptor<CareEvent>())
        XCTAssertTrue(events.isEmpty)
    }

    func testBackfilledWateringDoesNotRegressSchedule() async throws {
        let (container, context, plant) = try makeStore()
        _ = container
        let recent = date(2026, 8, 21)
        let dueCheck = date(2026, 8, 31, 9)
        plant.lastWatered = recent
        plant.nextCareCheckDate = dueCheck
        try context.save()

        _ = try await PlantCareActions.logCare(
            kind: .watering,
            for: plant,
            date: date(2026, 8, 10),
            soilWasMoist: false,
            settings: settings,
            context: context
        )

        XCTAssertEqual(plant.lastWatered, recent)
        XCTAssertEqual(plant.nextCareCheckDate, dueCheck)
        XCTAssertEqual(plant.events.map(\.kind), [CareEventKind.watering.rawValue])
    }

    func testBackfilledFertilizingDoesNotRegressLastFertilized() async throws {
        let (container, context, plant) = try makeStore()
        _ = container
        let recent = date(2026, 8, 21)
        plant.lastFertilized = recent
        try context.save()

        _ = try await PlantCareActions.logCare(
            kind: .fertilizing,
            for: plant,
            date: date(2026, 8, 10),
            soilWasMoist: true,
            settings: settings,
            context: context
        )

        XCTAssertEqual(plant.lastFertilized, recent)
        XCTAssertEqual(plant.events.map(\.kind), [CareEventKind.fertilizing.rawValue])
    }

    func testManualFertilizerRejectsDryMedia() async throws {
        let (container, context, plant) = try makeStore()
        _ = container
        do {
            _ = try await PlantCareActions.logCare(
                kind: .fertilizing,
                for: plant,
                date: Date.now,
                soilWasMoist: false,
                settings: settings,
                context: context
            )
            XCTFail("Expected dry-media protection")
        } catch CareActionError.fertilizerRequiresMoistSoil {
            XCTAssertNil(plant.lastFertilized)
        }
    }

    private func makeStore(
        growthState: GrowthState = .automatic
    ) throws -> (ModelContainer, ModelContext, Plant) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Plant.self,
            CareEvent.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let plant = Plant(
            commonName: "Test Plant",
            scientificName: "Planta testii",
            wateringIntervalDays: 10,
            wateringTrigger: "Top layer dry",
            fertilizingIntervalDays: 30,
            fertilizingNotes: "Follow the label",
            seasonalWatering: .init(spring: 10, summer: 10, autumn: 10, winter: 10),
            growthState: growthState
        )
        context.insert(plant)
        try context.save()
        return (container, context, plant)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
