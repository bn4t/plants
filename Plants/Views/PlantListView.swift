import SwiftData
import SwiftUI

private enum GardenSort: String, CaseIterable, Identifiable {
    case nextCheck
    case name
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextCheck: "Next check"
        case .name: "Name"
        case .newest: "Recently added"
        }
    }

    var systemImage: String {
        switch self {
        case .nextCheck: "calendar"
        case .name: "textformat"
        case .newest: "clock"
        }
    }
}

struct PlantListView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query private var plants: [Plant]

    let namespace: Namespace.ID
    let addPlant: () -> Void
    let showSettings: () -> Void

    @State private var searchText = ""
    @State private var sort: GardenSort = .nextCheck
    @State private var plantPendingDelete: Plant?
    @State private var errorMessage: String?

    private var visiblePlants: [Plant] {
        let filtered = searchText.isEmpty
            ? plants
            : plants.filter {
                $0.commonName.localizedCaseInsensitiveContains(searchText)
                    || $0.scientificName.localizedCaseInsensitiveContains(searchText)
            }
        switch sort {
        case .nextCheck:
            return filtered.sorted {
                recommendation(for: $0).dueDate < recommendation(for: $1).dueDate
            }
        case .name:
            return filtered.sorted {
                $0.commonName.localizedStandardCompare($1.commonName) == .orderedAscending
            }
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        }
    }

    var body: some View {
        Group {
            if plants.isEmpty {
                emptyState
            } else if visiblePlants.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(
                                minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 150,
                                maximum: dynamicTypeSize.isAccessibilitySize ? 520 : 220
                            ),
                            spacing: 12
                        )],
                        spacing: 12
                    ) {
                        ForEach(visiblePlants) { plant in
                            NavigationLink(value: plant.id) {
                                GardenPlantCard(
                                    plant: plant,
                                    recommendation: recommendation(for: plant)
                                )
                                .matchedTransitionSource(id: plant.id, in: namespace)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    plantPendingDelete = plant
                                } label: {
                                    Label("Delete plant", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(BotanicalTheme.background)
        .navigationTitle("Garden")
        .searchable(text: $searchText, prompt: "Search plants")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button(action: showSettings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort plants", selection: $sort) {
                        ForEach(GardenSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort plants")
                .accessibilityValue(sort.title)

                Button(action: addPlant) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add plant")
            }
        }
        .alert("Delete this plant?", isPresented: Binding(
            get: { plantPendingDelete != nil },
            set: { if !$0 { plantPendingDelete = nil } }
        ), presenting: plantPendingDelete) { plant in
            Button("Delete", role: .destructive) { delete(plant) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its care history and pending reminder will also be removed.")
        }
        .alert("Could not delete plant", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Grow Your Garden", systemImage: "leaf")
        } description: {
            Text("Add a photo to identify a plant, then get reminders to check its soil.")
        } actions: {
            Button(action: addPlant) {
                Label("Add First Plant", systemImage: "camera.fill")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recommendation(for plant: Plant) -> CareRecommendation {
        CareRecommendationEngine.recommendation(
            for: plant.careInput(),
            hemisphere: settings.hemisphere
        )
    }

    private func delete(_ plant: Plant) {
        NotificationService.shared.cancel(for: plant.id)
        modelContext.delete(plant)
        do {
            try modelContext.save()
            plantPendingDelete = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
