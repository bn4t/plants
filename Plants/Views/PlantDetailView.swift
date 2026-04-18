import SwiftData
import SwiftUI

struct PlantDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var plant: Plant

    @State private var showingIntervalEditor = false
    @State private var showingDeleteAlert = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PlantPhotoView(photoData: plant.photo)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plant.commonName.isEmpty ? "Unnamed plant" : plant.commonName)
                        .font(.largeTitle)
                        .fontWeight(.semibold)

                    if !plant.scientificName.isEmpty {
                        Text(plant.scientificName)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                }

                DetailCard(title: "Watering") {
                    LabeledValueRow(label: "Next", value: relativeDateText(for: plant.nextWateringDate))
                    LabeledValueRow(label: "Every", value: "\(plant.wateringIntervalDays) days")

                    if !plant.wateringTrigger.isEmpty {
                        Text(plant.wateringTrigger)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    Button(plant.wateredToday ? "Watered today" : "Water now") {
                        Task {
                            await handleWaterNow()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(plant.wateredToday)
                }

                if plant.fertilizingIntervalDays > 0 {
                    DetailCard(title: "Fertilizing") {
                        LabeledValueRow(
                            label: "Next",
                            value: relativeDateText(for: plant.nextFertilizingDate)
                        )
                        LabeledValueRow(label: "Every", value: "\(plant.fertilizingIntervalDays) days")

                        if !plant.fertilizingNotes.isEmpty {
                            Text(plant.fertilizingNotes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        Button(plant.fertilizedToday ? "Fertilized today" : "Fertilize now") {
                            Task {
                                await handleFertilizeNow()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(plant.fertilizedToday)
                    }
                }

                DetailCard(title: "History") {
                    PlantHistoryView(plant: plant)
                }

                DetailCard(title: "Info") {
                    LabeledValueRow(label: "Light", value: lightText(for: plant.lightRequirement))

                    if !plant.toxicityNote.isEmpty {
                        LabeledValueRow(label: "Toxicity", value: plant.toxicityNote)
                    }

                    if !plant.careNote.isEmpty {
                        LabeledValueRow(label: "Care note", value: plant.careNote)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("Plant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit intervals") {
                        showingIntervalEditor = true
                    }

                    #if DEBUG
                    Button("Simulate overdue (debug)") {
                        simulateOverdue()
                    }
                    #endif

                    Button("Delete plant", role: .destructive) {
                        showingDeleteAlert = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            seedInitialEventsIfNeeded()
        }
        .sheet(isPresented: $showingIntervalEditor) {
            NavigationStack {
                IntervalEditorView(plant: plant) { message in
                    errorMessage = message
                }
            }
        }
        .alert("Delete this plant?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deletePlant()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will cancel its reminders. This cannot be undone.")
        }
        .alert("Something went wrong", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func handleWaterNow() async {
        do {
            try await PlantCareActions.markWatered(plant, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleFertilizeNow() async {
        do {
            try await PlantCareActions.markFertilized(plant, context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private func simulateOverdue() {
        let calendar = Calendar.current
        plant.lastWatered = calendar.date(byAdding: .day, value: -(plant.wateringIntervalDays + 2), to: .now)
        if plant.fertilizingIntervalDays > 0 {
            plant.lastFertilized = calendar.date(byAdding: .day, value: -(plant.fertilizingIntervalDays + 2), to: .now)
        }
        try? modelContext.save()
    }
    #endif

    private func seedInitialEventsIfNeeded() {
        var changed = false
        if let lastWatered = plant.lastWatered,
           !plant.events.contains(where: { $0.kind == CareEventKind.water.rawValue }) {
            modelContext.insert(CareEvent(kind: .water, date: lastWatered, plant: plant))
            changed = true
        }
        if plant.fertilizingIntervalDays > 0,
           let lastFertilized = plant.lastFertilized,
           !plant.events.contains(where: { $0.kind == CareEventKind.fertilize.rawValue }) {
            modelContext.insert(CareEvent(kind: .fertilize, date: lastFertilized, plant: plant))
            changed = true
        }
        if changed {
            try? modelContext.save()
        }
    }

    private func deletePlant() {
        NotificationService.shared.cancelAll(for: plant.id)
        modelContext.delete(plant)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func relativeDateText(for date: Date?) -> String {
        guard let date else { return "Not scheduled" }

        let daysAway = Calendar.current.dateComponents([.day], from: .now, to: date).day ?? 0
        if daysAway < 0 {
            let overdueDays = abs(daysAway)
            return "Overdue by \(overdueDays) \(overdueDays == 1 ? "day" : "days")"
        }

        if daysAway == 0 {
            return "Due today"
        }

        if daysAway <= 14 {
            return date.formatted(.relative(presentation: .named))
        }

        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func lightText(for value: String) -> String {
        switch value {
        case "low":
            return "Low"
        case "bright_indirect":
            return "Bright indirect"
        case "direct_sun":
            return "Direct sun"
        default:
            return "Medium"
        }
    }
}

private struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LabeledValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

private struct IntervalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let plant: Plant
    let onError: (String) -> Void

    @State private var wateringIntervalDays: Int
    @State private var fertilizingIntervalDays: Int

    init(plant: Plant, onError: @escaping (String) -> Void) {
        self.plant = plant
        self.onError = onError
        _wateringIntervalDays = State(initialValue: plant.wateringIntervalDays)
        _fertilizingIntervalDays = State(initialValue: plant.fertilizingIntervalDays)
    }

    var body: some View {
        Form {
            Stepper("Water every \(wateringIntervalDays) days", value: $wateringIntervalDays, in: 1...60)
            Stepper(
                "Fertilize every \(fertilizingIntervalDays) days",
                value: $fertilizingIntervalDays,
                in: 0...120
            )
            Text("Set fertilizing to 0 to disable reminders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Edit intervals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await save()
                    }
                }
            }
        }
    }

    private func save() async {
        plant.wateringIntervalDays = wateringIntervalDays
        plant.fertilizingIntervalDays = fertilizingIntervalDays

        do {
            try modelContext.save()
            await NotificationService.shared.scheduleWater(for: plant)
            await NotificationService.shared.scheduleFertilize(for: plant)
            dismiss()
        } catch {
            onError(error.localizedDescription)
            dismiss()
        }
    }
}
