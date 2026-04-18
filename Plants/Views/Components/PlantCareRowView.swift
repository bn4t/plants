import SwiftData
import SwiftUI
import UIKit

struct PlantCareRowView: View {
    @Environment(\.modelContext) private var modelContext

    let plant: Plant
    var onError: (String) -> Void = { _ in }

    private var waterDue: Bool {
        plant.daysUntilWatering <= 0
    }

    private var fertilizeDue: Bool {
        guard let days = plant.daysUntilFertilizing else { return false }
        return days <= 0
    }

    var body: some View {
        HStack(spacing: 12) {
            PlantPhotoView(photoData: plant.photo, cornerRadius: 12)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(plant.commonName.isEmpty ? "Unnamed plant" : plant.commonName)
                    .font(.headline)
                    .lineLimit(1)

                Text(captionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if waterDue {
                    CareActionButton(
                        systemName: "drop.fill",
                        tint: .blue,
                        accessibilityLabel: "Mark \(plant.commonName) as watered"
                    ) {
                        await markWatered()
                    }
                }

                if fertilizeDue {
                    CareActionButton(
                        systemName: "leaf.fill",
                        tint: .green,
                        accessibilityLabel: "Mark \(plant.commonName) as fertilized"
                    ) {
                        await markFertilized()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var captionText: String {
        let waterPart: String? = {
            guard waterDue else { return nil }
            let days = plant.daysUntilWatering
            if days == 0 { return "Water due today" }
            let count = abs(days)
            return "Water overdue by \(count) \(count == 1 ? "day" : "days")"
        }()

        let fertilizePart: String? = {
            guard fertilizeDue, let days = plant.daysUntilFertilizing else { return nil }
            if days == 0 { return "fertilizer due today" }
            let count = abs(days)
            return "fertilizer overdue by \(count) \(count == 1 ? "day" : "days")"
        }()

        switch (waterPart, fertilizePart) {
        case let (water?, fertilizer?):
            return "\(water) · \(fertilizer)"
        case let (water?, nil):
            return water
        case let (nil, fertilizer?):
            return fertilizer.prefix(1).uppercased() + fertilizer.dropFirst()
        case (nil, nil):
            return ""
        }
    }

    private func markWatered() async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            try await PlantCareActions.markWatered(plant, context: modelContext)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func markFertilized() async {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            try await PlantCareActions.markFertilized(plant, context: modelContext)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct CareActionButton: View {
    let systemName: String
    let tint: Color
    let accessibilityLabel: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.15), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
    }
}
