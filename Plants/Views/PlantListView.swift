import SwiftData
import SwiftUI

struct PlantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allPlants: [Plant]

    @State private var showingAddPlant = false
    @State private var showingSettings = false
    @State private var plantPendingDelete: Plant?
    @State private var deleteErrorMessage: String?

    private var sortedPlants: [Plant] {
        allPlants.sorted {
            ($0.nextWateringDate ?? .distantPast) < ($1.nextWateringDate ?? .distantPast)
        }
    }

    private func needsCare(_ plant: Plant) -> Bool {
        if plant.needsInitialWatering { return true }
        if let days = plant.daysUntilWatering, days <= 0 { return true }
        if plant.needsInitialFertilizing { return true }
        if let days = plant.daysUntilFertilizing, days <= 0 { return true }
        return false
    }

    private var needsCarePlants: [Plant] {
        sortedPlants.filter(needsCare)
    }

    private var restPlants: [Plant] {
        sortedPlants.filter { !needsCare($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedPlants.isEmpty {
                    ContentUnavailableView(
                        "No plants yet",
                        systemImage: "leaf",
                        description: Text("Tap + to add your first plant.")
                    )
                } else {
                    plantsList
                }
            }
            .navigationTitle("Plants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddPlant = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add Plant")
                }
            }
            .sheet(isPresented: $showingAddPlant) {
                NavigationStack {
                    AddPlantView()
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                if Secrets.openRouterAPIKey == nil {
                    showingSettings = true
                }
            }
            .alert(
                "Delete this plant?",
                isPresented: deleteAlertBinding,
                presenting: plantPendingDelete
            ) { plant in
                Button("Delete", role: .destructive) {
                    delete(plant)
                }
                Button("Cancel", role: .cancel) {
                    plantPendingDelete = nil
                }
            } message: { _ in
                Text("This will cancel its reminders. This cannot be undone.")
            }
            .alert("Something went wrong", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {
                    deleteErrorMessage = nil
                }
            } message: {
                Text(deleteErrorMessage ?? "Unknown error")
            }
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { plantPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    plantPendingDelete = nil
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    private func delete(_ plant: Plant) {
        NotificationService.shared.cancelAll(for: plant.id)
        modelContext.delete(plant)

        do {
            try modelContext.save()
            plantPendingDelete = nil
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var plantsList: some View {
        let hasCare = !needsCarePlants.isEmpty
        List {
            if hasCare {
                Section("Needs care") {
                    ForEach(needsCarePlants) { plant in
                        careRow(for: plant)
                    }
                }
                Section("All plants") {
                    ForEach(restPlants) { plant in
                        plantRow(for: plant)
                    }
                }
            } else {
                ForEach(restPlants) { plant in
                    plantRow(for: plant)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func careRow(for plant: Plant) -> some View {
        NavigationLink {
            PlantDetailView(plant: plant)
        } label: {
            PlantCareRowView(plant: plant) { message in
                deleteErrorMessage = message
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                plantPendingDelete = plant
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func plantRow(for plant: Plant) -> some View {
        NavigationLink {
            PlantDetailView(plant: plant)
        } label: {
            PlantRowView(plant: plant)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                plantPendingDelete = plant
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
