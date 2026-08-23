import Foundation

enum CareCheckOutcome: String, CaseIterable, Codable, Sendable, Identifiable {
    case dryAndWatered
    case stillDamp
    case remindTomorrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dryAndWatered: "Dry, watered"
        case .stillDamp: "Still damp"
        case .remindTomorrow: "Remind tomorrow"
        }
    }

    var systemImage: String {
        switch self {
        case .dryAndWatered: "drop.fill"
        case .stillDamp: "drop.degreesign"
        case .remindTomorrow: "clock.arrow.circlepath"
        }
    }
}

enum GrowthState: String, CaseIterable, Codable, Sendable, Identifiable {
    case automatic
    case active
    case resting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .active: "Actively growing"
        case .resting: "Resting"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "wand.and.sparkles"
        case .active: "leaf.fill"
        case .resting: "pause.circle"
        }
    }
}

enum CareDueStatus: Equatable, Sendable {
    case overdue(days: Int)
    case today
    case upcoming(days: Int)

    var title: String {
        switch self {
        case .overdue(let days): "Overdue by \(days) \(days == 1 ? "day" : "days")"
        case .today: "Check today"
        case .upcoming(let days): days == 1 ? "Check tomorrow" : "Check in \(days) days"
        }
    }

    var isDue: Bool {
        switch self {
        case .overdue, .today: true
        case .upcoming: false
        }
    }
}

struct CareRecommendation: Equatable, Sendable {
    let status: CareDueStatus
    let dueDate: Date
    let predictedIntervalDays: Int
    let learnedCycleCount: Int
    let reason: String
    let season: Season
    let fertilizerDue: Bool
    let fertilizerActive: Bool
    let availableActions: [CareCheckOutcome]

    var displayStatus: String {
        switch status {
        case .overdue, .today:
            status.title
        case .upcoming(let days):
            switch days {
            case 1:
                "Check tomorrow"
            case 2...7:
                "Check in \(days) days"
            default:
                "Check \(dueDate.formatted(.dateTime.month(.abbreviated).day()))"
            }
        }
    }
}

struct CareEventSnapshot: Equatable, Sendable {
    let kind: CareEventKind
    let date: Date
}

struct CareRecommendationInput: Equatable, Sendable {
    let seasonalWatering: SeasonalWatering
    let events: [CareEventSnapshot]
    let lastWatered: Date?
    let lastFertilized: Date?
    let nextCareCheckDate: Date?
    let fertilizingIntervalDays: Int
    let growthState: GrowthState
}
