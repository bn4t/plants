import SwiftData
import SwiftUI

struct CareCheckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    let plant: Plant
    let onCompleted: (CareActionReceipt) -> Void

    @State private var includeFertilizer = false
    @State private var confirmedGrowth: GrowthState = .automatic
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var recommendation: CareRecommendation {
        CareRecommendationEngine.recommendation(
            for: plant.careInput(),
            hemisphere: settings.hemisphere
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        PlantPhotoView(photoData: plant.photo, cornerRadius: 14)
                            .frame(width: 68, height: 68)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(plant.commonName.isEmpty ? "Unnamed plant" : plant.commonName)
                                .font(.headline)
                            StatusPill(status: recommendation.status)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Label {
                        Text(plant.soilCheckGuidance)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "hand.tap.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .combine)

                    Button {
                        Task { await save(.dryAndWatered) }
                    } label: {
                        outcomeLabel(
                            .dryAndWatered,
                            subtitle: "Log watering and learn this plant's rhythm"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BotanicalTheme.water)
                    .keyboardShortcut(.defaultAction)
                    .careOutcomeRow()

                    Button {
                        Task { await save(.stillDamp) }
                    } label: {
                        outcomeLabel(.stillDamp, subtitle: dampSubtitle)
                    }
                    .buttonStyle(.bordered)
                    .tint(BotanicalTheme.tint)
                    .careOutcomeRow()

                    Button {
                        Task { await save(.remindTomorrow) }
                    } label: {
                        outcomeLabel(
                            .remindTomorrow,
                            subtitle: "Move the reminder without changing the learned timing"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(BotanicalTheme.tint)
                    .careOutcomeRow()
                } header: {
                    Text("What does the potting mix feel like?")
                }

                if recommendation.fertilizerDue {
                    Section("Feeding") {
                        if plant.growthState == .automatic {
                            Picker("Visible growth", selection: $confirmedGrowth) {
                                Text("Not sure").tag(GrowthState.automatic)
                                Text("Actively growing").tag(GrowthState.active)
                                Text("Resting").tag(GrowthState.resting)
                            }
                        }
                        Toggle("Add feed with watering", isOn: $includeFertilizer)
                            .disabled(
                                plant.growthState == .resting
                                    || (plant.growthState == .automatic && confirmedGrowth != .active)
                            )
                        Text(feedingExplanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text(recommendation.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Check Soil")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .onChange(of: confirmedGrowth) {
                if confirmedGrowth != .active {
                    includeFertilizer = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Could not log care", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var dampSubtitle: String {
        let days = CareRecommendationEngine.dampRecheckDays(
            predictedIntervalDays: recommendation.predictedIntervalDays
        )
        return days == 1 ? "Check again tomorrow" : "Check again in \(days) days"
    }

    private var feedingExplanation: String {
        if plant.growthState == .resting || confirmedGrowth == .resting {
            "Feeding is paused while the plant is resting."
        } else if plant.growthState == .automatic && confirmedGrowth != .active {
            "Confirm the plant is actively growing to add feed."
        } else {
            "Only feed moist potting mix and follow the fertilizer label."
        }
    }

    private func outcomeLabel(_ outcome: CareCheckOutcome, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: outcome.systemImage)
                .symbolRenderingMode(.monochrome)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(outcome.title)
        .accessibilityHint(subtitle)
    }

    private func save(_ outcome: CareCheckOutcome) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let receipt = try await PlantCareActions.apply(
                outcome,
                to: plant,
                includeFertilizer: outcome == .dryAndWatered && includeFertilizer,
                confirmedGrowthState: plant.growthState == .automatic && confirmedGrowth != .automatic
                    ? confirmedGrowth
                    : nil,
                settings: settings.snapshot,
                context: modelContext
            )
            onCompleted(receipt)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func careOutcomeRow() -> some View {
        controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }
}
