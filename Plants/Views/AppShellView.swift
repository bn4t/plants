import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case garden
}

private enum AppSheet: Identifiable {
    case addPlant
    case settings

    var id: Int {
        switch self {
        case .addPlant: 0
        case .settings: 1
        }
    }
}

struct AppShellView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @Query private var plants: [Plant]

    @State private var selectedTab: AppTab = .today
    @State private var todayPath: [UUID] = []
    @State private var gardenPath: [UUID] = []
    @State private var presentedSheet: AppSheet?
    @Namespace private var plantTransition

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "checkmark.circle", value: .today) {
                NavigationStack(path: $todayPath) {
                    TodayView(
                        namespace: plantTransition,
                        addPlant: { presentedSheet = .addPlant },
                        showSettings: { presentedSheet = .settings }
                    )
                    .navigationDestination(for: UUID.self) { id in
                        destination(for: id)
                    }
                }
            }

            Tab("Garden", systemImage: "leaf", value: .garden) {
                NavigationStack(path: $gardenPath) {
                    PlantListView(
                        namespace: plantTransition,
                        addPlant: { presentedSheet = .addPlant },
                        showSettings: { presentedSheet = .settings }
                    )
                    .navigationDestination(for: UUID.self) { id in
                        destination(for: id)
                    }
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addPlant:
                NavigationStack { AddPlantView() }
            case .settings:
                NavigationStack { SettingsView() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plantNotificationOpened)) { notification in
            guard let id = notification.userInfo?["plantId"] as? UUID else { return }
            selectedTab = .today
            todayPath = [id]
        }
        .onReceive(NotificationCenter.default.publisher(for: .plantCareActionCompleted)) { _ in
            selectedTab = .today
        }
        .onChange(of: settings.hemisphere) {
            Task {
                await NotificationService.shared.rescheduleAll(
                    for: plants,
                    settings: settings.snapshot
                )
            }
        }
    }

    @ViewBuilder
    private func destination(for id: UUID) -> some View {
        if let plant = plants.first(where: { $0.id == id }) {
            if reduceMotion {
                PlantDetailView(plant: plant, namespace: plantTransition)
                    .toolbar(.hidden, for: .tabBar)
            } else {
                PlantDetailView(plant: plant, namespace: plantTransition)
                    .navigationTransition(.zoom(sourceID: id, in: plantTransition))
                    .toolbar(.hidden, for: .tabBar)
            }
        } else {
            ContentUnavailableView(
                "Plant not found",
                systemImage: "leaf",
                description: Text("It may have been removed.")
            )
        }
    }
}
