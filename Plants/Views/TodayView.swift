import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query private var plants: [Plant]

    let namespace: Namespace.ID
    let addPlant: () -> Void
    let showSettings: () -> Void

    @State private var selectedPlant: Plant?
    @State private var undoReceipt: CareActionReceipt?
    @State private var errorMessage: String?

    private var recommendations: [(Plant, CareRecommendation)] {
        plants
            .map {
                (
                    $0,
                    CareRecommendationEngine.recommendation(
                        for: $0.careInput(),
                        hemisphere: settings.hemisphere
                    )
                )
            }
            .sorted { $0.1.dueDate < $1.1.dueDate }
    }

    private var overdue: [(Plant, CareRecommendation)] {
        recommendations.filter {
            if case .overdue = $0.1.status { return true }
            return false
        }
    }

    private var today: [(Plant, CareRecommendation)] {
        recommendations.filter { $0.1.status == .today }
    }

    private var upcoming: [(Plant, CareRecommendation)] {
        recommendations.filter { !$0.1.status.isDue }
    }

    var body: some View {
        Group {
            if plants.isEmpty {
                emptyState
            } else {
                careList
            }
        }
        .background(BotanicalTheme.background)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: showSettings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(item: $selectedPlant) { plant in
            CareCheckSheet(plant: plant) { receipt in
                withAnimation(reduceMotion ? nil : .snappy) {
                    undoReceipt = receipt
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plantCareActionCompleted)) { notification in
            guard let receipt = notification.object as? CareActionReceipt else { return }
            withAnimation(reduceMotion ? nil : .snappy) {
                undoReceipt = receipt
            }
        }
        .overlay(alignment: .bottom) {
            // The plant is resolved at render time: on a cold start the query
            // may still be empty when the notification lands.
            if let receipt = undoReceipt,
               let plant = plants.first(where: { $0.id == receipt.plantID }) {
                CareToast(message: receipt.message) {
                    Task { await undo(receipt, for: plant) }
                }
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: undoReceipt?.id) {
            guard undoReceipt != nil else { return }
            do {
                try await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 15 : 8))
            } catch {
                return
            }
            withAnimation(reduceMotion ? nil : .snappy) {
                undoReceipt = nil
            }
        }
        .alert("Care could not be updated", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var careList: some View {
        List {
            seasonalContext
                .listRowBackground(Color.clear)
                .listRowInsets(.init(top: 4, leading: 16, bottom: 8, trailing: 16))

            if !overdue.isEmpty {
                careSection("Overdue", systemImage: "exclamationmark.circle.fill", items: overdue)
            }
            if !today.isEmpty {
                careSection("Today", systemImage: "checkmark.circle.fill", items: today)
            }
            if overdue.isEmpty && today.isEmpty {
                allCaughtUp
            }
            if !upcoming.isEmpty {
                careSection(
                    "Upcoming",
                    systemImage: "calendar",
                    items: Array(upcoming.prefix(6)),
                    showsOverflowFooter: upcoming.count > 6
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Plants Yet", systemImage: "leaf")
        } description: {
            Text("Add a photo to identify your first plant and create its care plan.")
        } actions: {
            Button(action: addPlant) {
                Label("Add First Plant", systemImage: "camera.fill")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }

    private var seasonalContext: some View {
        let season = Season.current(hemisphere: settings.hemisphere)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: season.systemImage)
                .foregroundStyle(SeasonBadge(season: season).color)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(season.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(season.indoorNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func careSection(
        _ title: String,
        systemImage: String,
        items: [(Plant, CareRecommendation)],
        showsOverflowFooter: Bool = false
    ) -> some View {
        Section {
            ForEach(items, id: \.0.id) { plant, recommendation in
                NavigationLink(value: plant.id) {
                    CareTaskRow(
                        plant: plant,
                        recommendation: recommendation,
                        showsCheckAction: recommendation.status.isDue,
                        onCheck: { selectedPlant = plant }
                    )
                    .matchedTransitionSource(id: plant.id, in: namespace)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(plant.commonName), \(recommendation.displayStatus), \(plant.soilCheckGuidance)"
                )
                .accessibilityHint("Opens plant details")
            }
        } header: {
            Label(title, systemImage: systemImage)
        } footer: {
            if showsOverflowFooter {
                Text("Showing the next 6 checks. Every plant is in the Garden tab.")
            }
        }
    }

    private var allCaughtUp: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("All caught up")
                        .font(.headline)
                    if let next = upcoming.first {
                        Text("Next check: \(next.0.commonName), \(next.1.dueDate.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("There are no scheduled soil checks.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
        }
    }

    private func undo(_ receipt: CareActionReceipt, for plant: Plant) async {
        do {
            try await PlantCareActions.undo(
                receipt,
                plant: plant,
                settings: settings.snapshot,
                context: modelContext
            )
            withAnimation(reduceMotion ? nil : .snappy) {
                undoReceipt = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
