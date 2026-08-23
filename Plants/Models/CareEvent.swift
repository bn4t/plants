import Foundation
import SwiftData

@Model
final class CareEvent {
    @Attribute(.unique) var id: UUID
    var kind: String
    var date: Date
    var plant: Plant?

    init(id: UUID = UUID(), kind: CareEventKind, date: Date = .now, plant: Plant? = nil) {
        self.id = id
        self.kind = kind.rawValue
        self.date = date
        self.plant = plant
    }
}

enum CareEventKind: String, CaseIterable, Codable, Sendable {
    case watering = "water"
    case fertilizing = "fertilize"
    case soilCheckDamp

    var systemImage: String {
        switch self {
        case .watering: "drop.fill"
        case .fertilizing: "leaf.fill"
        case .soilCheckDamp: "drop.degreesign"
        }
    }
}
