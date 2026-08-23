import SwiftUI

struct CareTaskRow: View {
    let plant: Plant
    let recommendation: CareRecommendation
    let showsCheckAction: Bool
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                PlantPhotoView(photoData: plant.photo, cornerRadius: 14)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(plant.commonName.isEmpty ? "Unnamed plant" : plant.commonName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(recommendation.displayStatus)
                        .font(.subheadline.weight(recommendation.status.isDue ? .semibold : .regular))
                        .foregroundStyle(recommendation.status.isDue ? BotanicalTheme.attention : .secondary)
                    Text(plant.soilCheckGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(plant.commonName), \(recommendation.displayStatus), \(plant.soilCheckGuidance)")
            .accessibilityHint("Opens plant details")

            Spacer(minLength: 8)

            if showsCheckAction {
                Button("Check", action: onCheck)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(BotanicalTheme.tint)
                    .accessibilityLabel("Check \(plant.commonName)")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}
