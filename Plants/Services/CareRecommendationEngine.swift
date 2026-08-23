import Foundation

enum CareRecommendationEngine {
    static func recommendation(
        for input: CareRecommendationInput,
        hemisphere: Hemisphere,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> CareRecommendation {
        let season = Season.current(for: now, hemisphere: hemisphere, calendar: calendar)
        let learned = learnedInterval(
            from: input.events,
            for: season,
            hemisphere: hemisphere,
            calendar: calendar
        )
        let predicted = (learned.interval ?? input.seasonalWatering.interval(for: season))
            .clamped(to: 1...60)
        let dueDate = resolvedDueDate(
            nextCareCheckDate: input.nextCareCheckDate,
            lastWatered: input.lastWatered,
            predictedIntervalDays: predicted,
            calendar: calendar,
            now: now
        )
        let status = dueStatus(for: dueDate, calendar: calendar, now: now)
        let fertilizerActive = isFertilizerActive(
            growthState: input.growthState,
            season: season
        )
        let fertilizerDue = isFertilizerDue(
            lastFertilized: input.lastFertilized,
            intervalDays: input.fertilizingIntervalDays,
            isActive: fertilizerActive,
            calendar: calendar,
            now: now
        )
        let reason: String
        if let learnedInterval = learned.interval {
            reason = "Based on \(learned.count) recent watering cycles in \(season.displayName.lowercased()). Current pattern: about every \(learnedInterval) days. Your room and pot matter more than the calendar."
        } else {
            reason = "Starting with the \(season.displayName.lowercased()) species baseline. Each soil check will make this timing more personal."
        }

        return CareRecommendation(
            status: status,
            dueDate: dueDate,
            predictedIntervalDays: predicted,
            learnedCycleCount: learned.count,
            reason: reason,
            season: season,
            fertilizerDue: fertilizerDue,
            fertilizerActive: fertilizerActive,
            availableActions: CareCheckOutcome.allCases
        )
    }

    static func learnedInterval(
        from events: [CareEventSnapshot],
        for season: Season,
        hemisphere: Hemisphere,
        calendar: Calendar = .current
    ) -> (interval: Int?, count: Int) {
        let wateringDates = events
            .filter { $0.kind == .watering }
            .map(\.date)
            .sorted()

        guard wateringDates.count >= 3 else { return (nil, 0) }

        var intervals: [Int] = []
        for (earlier, later) in zip(wateringDates, wateringDates.dropFirst()) {
            guard Season.current(for: later, hemisphere: hemisphere, calendar: calendar) == season else {
                continue
            }
            let start = calendar.startOfDay(for: earlier)
            let end = calendar.startOfDay(for: later)
            guard let days = calendar.dateComponents([.day], from: start, to: end).day,
                  (1...60).contains(days)
            else {
                continue
            }
            intervals.append(days)
        }

        let samples = Array(intervals.suffix(3))
        guard samples.count >= 2 else { return (nil, samples.count) }
        let sorted = samples.sorted()
        let median: Int
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            median = Int((Double(sorted[upper - 1] + sorted[upper]) / 2).rounded())
        } else {
            median = sorted[sorted.count / 2]
        }
        return (median.clamped(to: 1...60), samples.count)
    }

    static func dampRecheckDays(predictedIntervalDays: Int) -> Int {
        Int((Double(predictedIntervalDays) * 0.2).rounded()).clamped(to: 1...3)
    }

    static func reminderDate(
        addingDays days: Int,
        to date: Date,
        hour: Int,
        minute: Int = 0,
        calendar: Calendar = .current
    ) -> Date {
        let shifted = calendar.date(byAdding: .day, value: days, to: date) ?? date
        return calendar.date(
            bySettingHour: hour.clamped(to: 0...23),
            minute: minute.clamped(to: 0...59),
            second: 0,
            of: shifted
        ) ?? shifted
    }

    static func isFertilizerActive(growthState: GrowthState, season: Season) -> Bool {
        switch growthState {
        case .active: true
        case .resting: false
        case .automatic: season != .winter
        }
    }

    private static func resolvedDueDate(
        nextCareCheckDate: Date?,
        lastWatered: Date?,
        predictedIntervalDays: Int,
        calendar: Calendar,
        now: Date
    ) -> Date {
        if let nextCareCheckDate { return nextCareCheckDate }
        guard let lastWatered else { return calendar.startOfDay(for: now) }
        return calendar.date(byAdding: .day, value: predictedIntervalDays, to: lastWatered) ?? lastWatered
    }

    private static func dueStatus(
        for dueDate: Date,
        calendar: Calendar,
        now: Date
    ) -> CareDueStatus {
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: dueDate)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day ?? 0
        if days < 0 { return .overdue(days: abs(days)) }
        if days == 0 { return .today }
        return .upcoming(days: days)
    }

    private static func isFertilizerDue(
        lastFertilized: Date?,
        intervalDays: Int,
        isActive: Bool,
        calendar: Calendar,
        now: Date
    ) -> Bool {
        guard isActive, intervalDays > 0 else { return false }
        guard let lastFertilized else { return true }
        guard let due = calendar.date(byAdding: .day, value: intervalDays, to: lastFertilized) else {
            return false
        }
        return due <= now
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
