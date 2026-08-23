import Foundation

enum Season: String, CaseIterable, Codable, Sendable {
    case spring
    case summer
    case autumn
    case winter

    static func current(
        for date: Date = .now,
        hemisphere: Hemisphere = .northern,
        calendar: Calendar = .current
    ) -> Season {
        let month = calendar.component(.month, from: date)
        return switch hemisphere {
        case .northern:
            switch month {
            case 3...5: .spring
            case 6...8: .summer
            case 9...11: .autumn
            default: .winter
            }
        case .southern:
            switch month {
            case 3...5: .autumn
            case 6...8: .winter
            case 9...11: .spring
            default: .summer
            }
        }
    }

    var displayName: String { rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .spring: "leaf"
        case .summer: "sun.max.fill"
        case .autumn: "leaf.fill"
        case .winter: "snowflake"
        }
    }

    var indoorNote: String {
        switch self {
        case .spring: "Changing light can change how quickly pots dry."
        case .summer: "Warm, bright rooms often need more frequent checks."
        case .autumn: "Shorter days can slow growth and drying."
        case .winter: "Heating can dry some pots quickly while cool rooms stay damp."
        }
    }
}

enum Hemisphere: String, Codable, Sendable, CaseIterable {
    case northern
    case southern

    var displayName: String {
        switch self {
        case .northern: "Northern"
        case .southern: "Southern"
        }
    }
}

struct SeasonalWatering: Codable, Sendable, Equatable {
    var spring: Int
    var summer: Int
    var autumn: Int
    var winter: Int

    static let `default` = SeasonalWatering(spring: 7, summer: 7, autumn: 7, winter: 7)

    func interval(for season: Season) -> Int {
        switch season {
        case .spring: spring
        case .summer: summer
        case .autumn: autumn
        case .winter: winter
        }
    }

    var clamped: SeasonalWatering {
        SeasonalWatering(
            spring: spring.clamped(to: 1...60),
            summer: summer.clamped(to: 1...60),
            autumn: autumn.clamped(to: 1...60),
            winter: winter.clamped(to: 1...60)
        )
    }

    var rangeDescription: String {
        let values = [spring, summer, autumn, winter]
        guard let minimum = values.min(), let maximum = values.max() else {
            return "Check weekly"
        }
        return minimum == maximum
            ? "Start by checking every \(minimum) days"
            : "Initial checks every \(minimum)–\(maximum) days by season"
    }

    static func derived(
        from base: Int,
        explicit: (spring: Int?, summer: Int?, autumn: Int?, winter: Int?) = (nil, nil, nil, nil)
    ) -> SeasonalWatering {
        let baseline = base.clamped(to: 1...60)
        return SeasonalWatering(
            spring: explicit.spring ?? baseline,
            summer: explicit.summer ?? baseline,
            autumn: explicit.autumn ?? baseline,
            winter: explicit.winter ?? baseline
        ).clamped
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
