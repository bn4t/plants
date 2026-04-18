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

enum CareEventKind: String {
    case water
    case fertilize
}
