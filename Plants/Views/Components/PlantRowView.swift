import SwiftUI

struct PlantRowView: View {
    let plant: Plant

    var body: some View {
        HStack(spacing: 12) {
            PlantPhotoView(photoData: plant.photo, cornerRadius: 12)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(plant.commonName.isEmpty ? "Unnamed plant" : plant.commonName)
                    .font(.headline)

                if !plant.scientificName.isEmpty {
                    Text(plant.scientificName)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        if plant.daysUntilWatering < 0 {
            let overdueDays = abs(plant.daysUntilWatering)
            return "Overdue by \(overdueDays) \(overdueDays == 1 ? "day" : "days")"
        }

        if plant.daysUntilWatering == 0 {
            return "Due today"
        }

        return "Due in \(plant.daysUntilWatering) \(plant.daysUntilWatering == 1 ? "day" : "days")"
    }

    private var statusColor: Color {
        if plant.daysUntilWatering < 0 {
            return .red
        }

        if plant.daysUntilWatering == 0 {
            return .orange
        }

        return .secondary
    }
}
