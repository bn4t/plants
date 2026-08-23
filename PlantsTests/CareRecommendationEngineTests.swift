import XCTest
@testable import Plants

final class CareRecommendationEngineTests: XCTestCase {
    private var zurichCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return calendar
    }

    func testSeasonMappingUsesHemisphere() {
        let march = date(2026, 3, 21)
        let december = date(2026, 12, 21)

        XCTAssertEqual(Season.current(for: march, hemisphere: .northern, calendar: zurichCalendar), .spring)
        XCTAssertEqual(Season.current(for: march, hemisphere: .southern, calendar: zurichCalendar), .autumn)
        XCTAssertEqual(Season.current(for: december, hemisphere: .northern, calendar: zurichCalendar), .winter)
        XCTAssertEqual(Season.current(for: december, hemisphere: .southern, calendar: zurichCalendar), .summer)
    }

    func testLearnedIntervalUsesMedianOfLastThreeCurrentSeasonCycles() {
        let events = [
            date(2026, 6, 1),
            date(2026, 6, 7),
            date(2026, 6, 15),
            date(2026, 6, 25)
        ].map { CareEventSnapshot(kind: .watering, date: $0) }

        let result = CareRecommendationEngine.learnedInterval(
            from: events,
            for: .summer,
            hemisphere: .northern,
            calendar: zurichCalendar
        )

        XCTAssertEqual(result.interval, 8)
        XCTAssertEqual(result.count, 3)
    }

    func testLearningRequiresTwoValidCyclesAndIgnoresSameDayDuplicates() {
        let oneCycle = [date(2026, 6, 1), date(2026, 6, 8)]
            .map { CareEventSnapshot(kind: .watering, date: $0) }
        XCTAssertNil(CareRecommendationEngine.learnedInterval(
            from: oneCycle,
            for: .summer,
            hemisphere: .northern,
            calendar: zurichCalendar
        ).interval)

        let duplicates = [
            date(2026, 6, 1, 8),
            date(2026, 6, 1, 18),
            date(2026, 6, 8),
            date(2026, 6, 16)
        ].map { CareEventSnapshot(kind: .watering, date: $0) }
        let learned = CareRecommendationEngine.learnedInterval(
            from: duplicates,
            for: .summer,
            hemisphere: .northern,
            calendar: zurichCalendar
        )
        XCTAssertEqual(learned.interval, 8)
        XCTAssertEqual(learned.count, 2)
    }

    func testCycleIsAssignedToSeasonOfLaterWatering() {
        let events = [
            date(2026, 5, 25),
            date(2026, 6, 5),
            date(2026, 6, 15)
        ].map { CareEventSnapshot(kind: .watering, date: $0) }

        let summer = CareRecommendationEngine.learnedInterval(
            from: events,
            for: .summer,
            hemisphere: .northern,
            calendar: zurichCalendar
        )
        let spring = CareRecommendationEngine.learnedInterval(
            from: events,
            for: .spring,
            hemisphere: .northern,
            calendar: zurichCalendar
        )

        XCTAssertEqual(summer.interval, 11)
        XCTAssertEqual(summer.count, 2)
        XCTAssertNil(spring.interval)
    }

    func testDampSoilRecheckUsesTwentyPercentWithClamp() {
        XCTAssertEqual(CareRecommendationEngine.dampRecheckDays(predictedIntervalDays: 3), 1)
        XCTAssertEqual(CareRecommendationEngine.dampRecheckDays(predictedIntervalDays: 10), 2)
        XCTAssertEqual(CareRecommendationEngine.dampRecheckDays(predictedIntervalDays: 45), 3)
    }

    func testFertilizerGrowthStates() {
        XCTAssertTrue(CareRecommendationEngine.isFertilizerActive(growthState: .active, season: .winter))
        XCTAssertFalse(CareRecommendationEngine.isFertilizerActive(growthState: .resting, season: .summer))
        XCTAssertTrue(CareRecommendationEngine.isFertilizerActive(growthState: .automatic, season: .summer))
        XCTAssertFalse(CareRecommendationEngine.isFertilizerActive(growthState: .automatic, season: .winter))
    }

    func testUnknownLastWateredIsDueToday() {
        let now = date(2026, 8, 23, 14)
        let recommendation = CareRecommendationEngine.recommendation(
            for: input(lastWatered: nil),
            hemisphere: .northern,
            calendar: zurichCalendar,
            now: now
        )

        XCTAssertEqual(recommendation.status, .today)
        XCTAssertTrue(zurichCalendar.isDate(recommendation.dueDate, inSameDayAs: now))
    }

    func testReminderTimeSurvivesDSTBoundary() {
        let beforeDST = date(2026, 3, 28, 9)
        let reminder = CareRecommendationEngine.reminderDate(
            addingDays: 1,
            to: beforeDST,
            hour: 9,
            calendar: zurichCalendar
        )
        let components = zurichCalendar.dateComponents([.year, .month, .day, .hour], from: reminder)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 29)
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(reminder.timeIntervalSince(beforeDST), 23 * 60 * 60, accuracy: 1)
    }

    func testNotificationIdentifierReplacesPerPlant() {
        let plantID = UUID()
        XCTAssertEqual(
            NotificationService.notificationIdentifier(for: plantID),
            NotificationService.notificationIdentifier(for: plantID)
        )
        XCTAssertNotEqual(
            NotificationService.notificationIdentifier(for: plantID),
            NotificationService.notificationIdentifier(for: UUID())
        )
    }

    func testDisplayStatusUsesRelativeCopyForOneWeekThenShortDate() {
        let tomorrow = recommendation(status: .upcoming(days: 1), dueDate: date(2026, 8, 24))
        let thisWeek = recommendation(status: .upcoming(days: 6), dueDate: date(2026, 8, 29))
        let laterDate = date(2026, 9, 4)
        let later = recommendation(status: .upcoming(days: 12), dueDate: laterDate)

        XCTAssertEqual(tomorrow.displayStatus, "Check tomorrow")
        XCTAssertEqual(thisWeek.displayStatus, "Check in 6 days")
        XCTAssertEqual(
            later.displayStatus,
            "Check \(laterDate.formatted(.dateTime.month(.abbreviated).day()))"
        )
    }

    private func input(lastWatered: Date?) -> CareRecommendationInput {
        CareRecommendationInput(
            seasonalWatering: .init(spring: 8, summer: 7, autumn: 10, winter: 14),
            events: [],
            lastWatered: lastWatered,
            lastFertilized: nil,
            nextCareCheckDate: nil,
            fertilizingIntervalDays: 30,
            growthState: .automatic
        )
    }

    private func recommendation(status: CareDueStatus, dueDate: Date) -> CareRecommendation {
        CareRecommendation(
            status: status,
            dueDate: dueDate,
            predictedIntervalDays: 10,
            learnedCycleCount: 0,
            reason: "Test",
            season: .summer,
            fertilizerDue: false,
            fertilizerActive: true,
            availableActions: CareCheckOutcome.allCases
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        zurichCalendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
