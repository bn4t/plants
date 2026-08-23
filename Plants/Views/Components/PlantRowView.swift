import SwiftUI

struct GardenPlantCard: View {
    let plant: Plant
    let recommendation: CareRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlantPhotoView(photoData: plant.photo, cornerRadius: 18)
                .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 3) {
                Text(plant.commonName.isEmpty ? "Unnamed plant" : plant.commonName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !plant.scientificName.isEmpty {
                    Text(plant.scientificName)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Label(
                    recommendation.displayStatus,
                    systemImage: recommendation.status.isDue ? "exclamationmark.circle.fill" : "calendar"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(recommendation.status.isDue ? BotanicalTheme.attention : .secondary)
                .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            BotanicalTheme.elevatedSurface,
            in: RoundedRectangle(cornerRadius: BotanicalTheme.cardRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: BotanicalTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plant.commonName), \(recommendation.displayStatus)")
        .accessibilityHint("Opens plant details")
    }
}
