import SwiftData
import SwiftUI
import UIKit

private enum PlantDetailSheet: Identifiable {
    case checkSoil
    case logCare
    case edit

    var id: Int {
        switch self {
        case .checkSoil: 0
        case .logCare: 1
        case .edit: 2
        }
    }
}

struct PlantDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    let plant: Plant
    let namespace: Namespace.ID

    @State private var presentedSheet: PlantDetailSheet?
    @State private var undoReceipt: CareActionReceipt?
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var showsBarTitle = false

    private var recommendation: CareRecommendation {
        CareRecommendationEngine.recommendation(
            for: plant.careInput(),
            hemisphere: settings.hemisphere
        )
    }

    private var heroHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 470 : 380
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                hero
                careSummary
                adaptivePlan
                feeding
                facts
                PlantHistoryView(plant: plant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentSurface()
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top >= heroHeight - 64
        } action: { _, shouldShowTitle in
            withAnimation(.easeInOut(duration: 0.15)) {
                showsBarTitle = shouldShowTitle
            }
        }
        .background(BotanicalTheme.background)
        .ignoresSafeArea(edges: .top)
        .navigationTitle(plant.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(plant.commonName)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(showsBarTitle ? 1 : 0)
                    .accessibilityHidden(!showsBarTitle)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        presentedSheet = .edit
                    } label: {
                        Label("Edit plant", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete plant", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Plant options")
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 8) {
                if let undoReceipt {
                    CareToast(message: undoReceipt.message) {
                        Task { await undo(undoReceipt) }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                actionBar
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .checkSoil:
                CareCheckSheet(plant: plant, onCompleted: showUndo)
            case .logCare:
                ManualCareSheet(plant: plant, onCompleted: showUndo)
            case .edit:
                PlantEditorSheet(plant: plant)
            }
        }
        .alert("Delete \(plant.commonName)?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deletePlant() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its care history and reminder will also be removed.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            PlantPhotoView(photoData: plant.photo, cornerRadius: 0)
                .frame(height: heroHeight)
            LinearGradient(
                colors: [.clear, .black.opacity(0.68)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 5) {
                SeasonBadge(season: recommendation.season, compact: true, overMedia: true)
                Text(plant.commonName.isEmpty ? "Unnamed plant" : plant.commonName)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                if !plant.scientificName.isEmpty {
                    Text(plant.scientificName)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(20)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plant.commonName), \(plant.scientificName)")
    }

    private var careSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "hand.tap.fill")
                .font(.title2)
                .foregroundStyle(BotanicalTheme.water)
                .frame(width: 42, height: 42)
                .background(BotanicalTheme.water.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(plant.soilCheckGuidance)
                    .font(.headline)
                StatusPill(status: recommendation.status)
                Text("The reminder is a prompt to check, not an instruction to water.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentSurface()
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var adaptivePlan: some View {
        let estimateLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))

        return VStack(alignment: .leading, spacing: 14) {
            Label("Adaptive check plan", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            SeasonStrip(current: recommendation.season, intervals: plant.seasonalWatering)
            Divider()
            estimateLayout {
                Label("Current estimate", systemImage: "calendar")
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }
                Text("\(recommendation.predictedIntervalDays) days")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            Text(recommendation.reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .contentSurface()
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var feeding: some View {
        if plant.fertilizingIntervalDays > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Feeding", systemImage: "leaf.fill")
                        .font(.headline)
                    Spacer()
                    Label(plant.growthState.title, systemImage: plant.growthState.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(feedingStatusText)
                    .font(.subheadline.weight(.medium))
                if !plant.fertilizingNotes.isEmpty {
                    Text(plant.fertilizingNotes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Only feed actively growing plants in moist potting mix. Follow the product label.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentSurface()
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var facts: some View {
        if !plant.lightRequirement.isEmpty || !plant.toxicityNote.isEmpty || !plant.careNote.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Care notes")
                    .font(.headline)
                if !plant.lightRequirement.isEmpty {
                    factRow("Light", value: lightDescription, systemImage: "sun.max")
                }
                if !plant.toxicityNote.isEmpty {
                    factRow("Safety", value: plant.toxicityNote, systemImage: "pawprint")
                }
                if !plant.careNote.isEmpty {
                    factRow("Tip", value: plant.careNote, systemImage: "sparkles")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentSurface()
            .padding(.horizontal, 16)
        }
    }

    private var actionBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        return GlassEffectContainer(spacing: 12) {
            layout {
                Button {
                    presentedSheet = .checkSoil
                } label: {
                    Label("Check Soil", systemImage: "hand.tap.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button {
                    presentedSheet = .logCare
                } label: {
                    Label("Log Care", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var feedingStatusText: String {
        if !recommendation.fertilizerActive && plant.growthState == .resting {
            "Paused while resting"
        } else if recommendation.fertilizerDue {
            "Due with the next suitable watering"
        } else {
            "Not currently due"
        }
    }

    private var lightDescription: String {
        switch plant.lightRequirement {
        case "low": "Low light"
        case "bright_indirect": "Bright indirect light"
        case "direct_sun": "Direct sun"
        default: "Medium light"
        }
    }

    private func factRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(BotanicalTheme.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func showUndo(_ receipt: CareActionReceipt) {
        withAnimation(reduceMotion ? nil : .snappy) {
            undoReceipt = receipt
        }
    }

    private func undo(_ receipt: CareActionReceipt) async {
        do {
            try await PlantCareActions.undo(
                receipt,
                plant: plant,
                settings: settings.snapshot,
                context: modelContext
            )
            withAnimation(reduceMotion ? nil : .snappy) { undoReceipt = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePlant() {
        NotificationService.shared.cancel(for: plant.id)
        modelContext.delete(plant)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ManualCareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    let plant: Plant
    let onCompleted: (CareActionReceipt) -> Void

    @State private var kind: CareEventKind = .watering
    @State private var date = Date.now
    @State private var soilIsMoist = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Care type") {
                    Picker("Care type", selection: $kind) {
                        Label("Watered", systemImage: "drop.fill").tag(CareEventKind.watering)
                        Label("Fertilized", systemImage: "leaf.fill").tag(CareEventKind.fertilizing)
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date", selection: $date, in: ...Date.now)
                        // Inline calendar: the compact style's floating panel
                        // overlaps the section below on iOS 26.
                        .datePickerStyle(.graphical)
                }
                if kind == .fertilizing {
                    Section {
                        Toggle("Potting mix was moist", isOn: $soilIsMoist)
                        Text("Fertilizer should not be applied to dry potting mix.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log Care")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(kind == .fertilizing && !soilIsMoist)
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

    private func save() async {
        do {
            let receipt = try await PlantCareActions.logCare(
                kind: kind,
                for: plant,
                date: date,
                soilWasMoist: soilIsMoist,
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

private struct PlantEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings

    let plant: Plant

    @State private var commonName: String
    @State private var scientificName: String
    @State private var trigger: String
    @State private var seasonal: SeasonalWatering
    @State private var fertilizerInterval: Int
    @State private var fertilizerNotes: String
    @State private var growthState: GrowthState
    @State private var errorMessage: String?

    init(plant: Plant) {
        self.plant = plant
        _commonName = State(initialValue: plant.commonName)
        _scientificName = State(initialValue: plant.scientificName)
        _trigger = State(initialValue: plant.wateringTrigger)
        _seasonal = State(initialValue: plant.seasonalWatering)
        _fertilizerInterval = State(initialValue: plant.fertilizingIntervalDays)
        _fertilizerNotes = State(initialValue: plant.fertilizingNotes)
        _growthState = State(initialValue: plant.growthState)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Common name", text: $commonName)
                    TextField("Scientific name", text: $scientificName)
                        .textInputAutocapitalization(.never)
                }
                Section("Soil check") {
                    TextField("When should the soil be watered?", text: $trigger, axis: .vertical)
                    seasonalStepper("Spring", season: .spring)
                    seasonalStepper("Summer", season: .summer)
                    seasonalStepper("Autumn", season: .autumn)
                    seasonalStepper("Winter", season: .winter)
                    Text("These are starting check intervals. Observed watering cycles take priority.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Feeding") {
                    Stepper(
                        fertilizerInterval == 0 ? "No reminders" : "Every \(fertilizerInterval) days",
                        value: $fertilizerInterval,
                        in: 0...120,
                        step: 7
                    )
                    Picker("Growth state", selection: $growthState) {
                        ForEach(GrowthState.allCases) { state in
                            Label(state.title, systemImage: state.systemImage).tag(state)
                        }
                    }
                    TextField("Feeding notes", text: $fertilizerNotes, axis: .vertical)
                }
            }
            .navigationTitle("Edit plant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(commonName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Could not save changes", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func seasonalStepper(_ title: String, season: Season) -> some View {
        let binding = Binding(
            get: { seasonal.interval(for: season) },
            set: { value in
                switch season {
                case .spring: seasonal.spring = value
                case .summer: seasonal.summer = value
                case .autumn: seasonal.autumn = value
                case .winter: seasonal.winter = value
                }
            }
        )
        return Stepper(value: binding, in: 1...60) {
            Label("\(title): \(binding.wrappedValue) days", systemImage: season.systemImage)
        }
    }

    private func save() async {
        // If the pending check sits exactly on the baseline anchor
        // (lastWatered + predicted interval), re-derive it after edits so
        // changed intervals actually move the reminder. A damp/snoozed check
        // does not match the anchor and is left alone.
        let previousAnchor = plant.lastWatered.map {
            CareRecommendationEngine.reminderDate(
                addingDays: CareRecommendationEngine.recommendation(
                    for: plant.careInput(),
                    hemisphere: settings.hemisphere
                ).predictedIntervalDays,
                to: $0,
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
        }
        let previousCheck = plant.nextCareCheckDate

        plant.commonName = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.scientificName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.wateringTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.seasonalWatering = seasonal
        plant.fertilizingIntervalDays = fertilizerInterval
        plant.fertilizingNotes = fertilizerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        plant.growthState = growthState

        if let previousAnchor,
           let previousCheck,
           abs(previousCheck.timeIntervalSince(previousAnchor)) < 2,
           let lastWatered = plant.lastWatered {
            plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
                addingDays: CareRecommendationEngine.recommendation(
                    for: plant.careInput(),
                    hemisphere: settings.hemisphere
                ).predictedIntervalDays,
                to: lastWatered,
                hour: settings.reminderHour,
                minute: settings.reminderMinute
            )
        }

        do {
            try modelContext.save()
            await NotificationService.shared.scheduleSoilCheck(
                for: plant,
                settings: settings.snapshot
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
