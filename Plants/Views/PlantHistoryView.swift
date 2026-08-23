import SwiftUI

struct PlantHistoryView: View {
    let plant: Plant

    private var events: [CareEvent] {
        plant.events.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("History", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if events.isEmpty {
                Text("Care actions will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(events.prefix(12).enumerated()), id: \.element.id) { index, event in
                    eventRow(event)
                    if index < min(events.count, 12) - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func eventRow(_ event: CareEvent) -> some View {
        let kind = CareEventKind(rawValue: event.kind)
        return HStack(spacing: 12) {
            Image(systemName: kind?.systemImage ?? "questionmark.circle")
                .foregroundStyle(color(for: kind))
                .frame(width: 28, height: 28)
                .background(color(for: kind).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: kind))
                    .font(.subheadline.weight(.medium))
                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title(for: kind)), \(event.date.formatted(date: .long, time: .shortened))")
    }

    private func title(for kind: CareEventKind?) -> String {
        switch kind {
        case .watering: "Watered"
        case .fertilizing: "Fertilized"
        case .soilCheckDamp: "Soil still damp"
        case nil: "Care event"
        }
    }

    private func color(for kind: CareEventKind?) -> Color {
        switch kind {
        case .watering, .soilCheckDamp: BotanicalTheme.water
        case .fertilizing: BotanicalTheme.feeding
        case nil: .secondary
        }
    }
}
