import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

private enum AddPlantStep {
    case choosePhoto
    case connect(Data)
    case identifying(Data)
    case confirm(Data)
    case failed(Data, String)
}

private enum LastWateredChoice: String, CaseIterable, Identifiable {
    case unknown
    case today
    case anotherDate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unknown: "Not sure"
        case .today: "Today"
        case .anotherDate: "Choose date"
        }
    }
}

struct AddPlantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var existingPlants: [Plant]

    @State private var step: AddPlantStep = .choosePhoto
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var showingAdvanced = false
    @State private var draft = PlantDraft(identification: .manualFallback)
    @State private var lastWateredChoice: LastWateredChoice = .unknown
    @State private var lastWateredDate = Date.now
    @State private var isConnecting = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var notificationPrimerPlant: Plant?
    @State private var showingDiscardConfirmation = false
    @State private var didIdentify = false
    @State private var authService = OpenRouterAuthService()

    var body: some View {
        Group {
            switch step {
            case .confirm(let photo):
                confirmation(photo: photo)
            default:
                ScrollView {
                    switch step {
                    case .choosePhoto:
                        photoChooser
                    case .connect(let photo):
                        connectionPrompt(photo: photo)
                    case .identifying(let photo):
                        identifying(photo: photo)
                    case .failed(let photo, let message):
                        failure(photo: photo, message: message)
                    case .confirm:
                        EmptyView()
                    }

                }
                .contentMargins(16, for: .scrollContent)
            }
        }
        .background(BotanicalTheme.background)
        .navigationTitle("Add Plant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            if case .confirm = step {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave || isSaving)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .onChange(of: capturedImage) { _, image in
            guard let image else { return }
            use(image)
        }
        .interactiveDismissDisabled(hasProgress)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .sheet(item: $notificationPrimerPlant) { plant in
            NotificationPrimerView(plant: plant) {
                notificationPrimerPlant = nil
                dismiss()
            }
            .interactiveDismissDisabled()
        }
        .alert("Could not continue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Discard this plant?", isPresented: $showingDiscardConfirmation) {
            Button("Discard Plant", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("The selected photo, identification result, and any edits will be lost.")
        }
    }

    private var photoChooser: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(BotanicalTheme.tint.opacity(0.1))
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 210 : 280)
                Image(systemName: "camera.macro")
                    .font(.system(size: 72, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BotanicalTheme.tint)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Start with a clear photo")
                    .font(.title2.bold())
                Text("Fill the frame with the leaves and photograph the plant in good light.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Button {
                draft = PlantDraft(identification: .manualFallback)
                step = .confirm(Data())
            } label: {
                Label("Enter details without a photo", systemImage: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(BotanicalTheme.tint)
        }
    }

    private func connectionPrompt(photo: Data) -> some View {
        VStack(spacing: 20) {
            photoPreview(photo, height: previewHeight(regular: 260))
            ContentUnavailableView {
                Label("Connect for plant identification", systemImage: "sparkles")
            } description: {
                Text("Sign in to OpenRouter once. Plants receives a user-controlled key securely, with no copy and paste.")
            } actions: {
                Button {
                    Task { await connectAndIdentify(photo: photo) }
                } label: {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Label("Connect OpenRouter", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isConnecting)

                Button {
                    draft = PlantDraft(identification: .manualFallback)
                    step = .confirm(photo)
                } label: {
                    Label("Enter details manually", systemImage: "square.and.pencil")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func identifying(photo: Data) -> some View {
        VStack(spacing: 18) {
            ZStack {
                photoPreview(photo, height: previewHeight(regular: 280))
                Rectangle()
                    .fill(.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Identifying your plant")
                    .font(.title3.bold())
                Text("Swiss Cheese Plant")
                    .font(.headline)
                Text("Monstera deliciosa")
                    .font(.subheadline)
                Text("Preparing an adaptive care plan")
                    .font(.body)
            }
            .contentSurface()
            .redacted(reason: .placeholder)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Identifying plant")
        }
    }

    private func confirmation(photo: Data) -> some View {
        Form {
            if !photo.isEmpty {
                Section {
                    photoPreview(photo, height: previewHeight(regular: 230))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if didIdentify && draft.confidence == .low {
                Section {
                    Label(
                        "Identification confidence is low. Check the name before saving.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                TextField("Common name", text: $draft.commonName)
                TextField("Scientific name", text: $draft.scientificName)
                    .textInputAutocapitalization(.never)
                TextField("When is the potting mix dry enough?", text: $draft.wateringTrigger, axis: .vertical)
            } header: {
                Label("Identity and soil trigger", systemImage: "leaf")
            }

            Section {
                Picker("When?", selection: $lastWateredChoice) {
                    ForEach(LastWateredChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                if lastWateredChoice == .anotherDate {
                    DatePicker("Date", selection: $lastWateredDate, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
                Text(lastWateredChoice == .unknown
                     ? "Plants will ask you to check the soil today."
                     : "This starts the first soil-check estimate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Last watered", systemImage: "drop")
            }

            Section {
                DisclosureGroup("Advanced care plan", isExpanded: $showingAdvanced) {
                    SeasonStrip(
                        current: Season.current(hemisphere: settings.hemisphere),
                        intervals: draft.seasonalWatering
                    )
                    ForEach(Season.allCases, id: \.self) { season in
                        seasonalStepper(season)
                    }
                    Divider()
                    Stepper(
                        draft.fertilizingInterval == 0
                            ? "No feeding reminders"
                            : "Feed every \(draft.fertilizingInterval) days while growing",
                        value: $draft.fertilizingInterval,
                        in: 0...120,
                        step: 7
                    )
                    TextField("Feeding guidance", text: $draft.fertilizingNotes, axis: .vertical)
                    TextField("General care note", text: $draft.careNote, axis: .vertical)
                }
            } footer: {
                Text("Review the name and soil trigger, then tap Save.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func failure(photo: Data, message: String) -> some View {
        VStack(spacing: 20) {
            photoPreview(photo, height: previewHeight(regular: 260))
            ContentUnavailableView {
                Label("Identification did not finish", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button {
                    Task { await identify(photo: photo) }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glassProminent)
                Button {
                    draft = PlantDraft(identification: .manualFallback)
                    step = .confirm(photo)
                } label: {
                    Label("Enter details manually", systemImage: "square.and.pencil")
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var canSave: Bool {
        !draft.commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.wateringTrigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasProgress: Bool {
        switch step {
        case .connect, .identifying, .confirm, .failed:
            true
        case .choosePhoto:
            false
        }
    }

    private func cancel() {
        if hasProgress {
            showingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func photoPreview(_ data: Data, height: CGFloat) -> some View {
        PlantPhotoView(photoData: data.isEmpty ? nil : data, cornerRadius: 28)
            .frame(height: height)
    }

    private func previewHeight(regular: CGFloat) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? min(regular, 200) : regular
    }

    private func seasonalStepper(_ season: Season) -> some View {
        Stepper(value: seasonalIntervalBinding(for: season), in: 1...60) {
            Label(
                "\(season.displayName): \(draft.seasonalWatering.interval(for: season)) days",
                systemImage: season.systemImage
            )
            .font(.subheadline)
        }
    }

    private func seasonalIntervalBinding(for season: Season) -> Binding<Int> {
        Binding(
            get: { draft.seasonalWatering.interval(for: season) },
            set: { value in
                switch season {
                case .spring: draft.seasonalWatering.spring = value
                case .summer: draft.seasonalWatering.summer = value
                case .autumn: draft.seasonalWatering.autumn = value
                case .winter: draft.seasonalWatering.winter = value
                }
            }
        )
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                throw AddPlantError.unreadablePhoto
            }
            await MainActor.run { use(image) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func use(_ image: UIImage) {
        guard let data = PhotoProcessor.process(image) else {
            errorMessage = AddPlantError.unreadablePhoto.localizedDescription
            return
        }
        if Secrets.hasOpenRouterAPIKey {
            Task { await identify(photo: data) }
        } else {
            step = .connect(data)
        }
    }

    private func connectAndIdentify(photo: Data) async {
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await authService.connect()
            await identify(photo: photo)
        } catch OpenRouterConnectionError.cancelled {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func identify(photo: Data) async {
        step = .identifying(photo)
        do {
            let result = try await GeminiClient.shared.identify(
                imageJPEG: photo,
                hemisphere: settings.hemisphere
            )
            draft = PlantDraft(identification: result)
            didIdentify = true
            step = .confirm(photo)
        } catch is CancellationError {
            // Leaving the step at .identifying would pin the spinner forever.
            if case .identifying = step {
                step = .failed(photo, "The request was cancelled.")
            }
        } catch {
            step = .failed(photo, error.localizedDescription)
        }
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        let isFirstPlant = existingPlants.isEmpty

        let photo: Data?
        if case .confirm(let data) = step, !data.isEmpty {
            photo = data
        } else {
            photo = nil
        }
        let plant = Plant(
            commonName: draft.commonName.trimmingCharacters(in: .whitespacesAndNewlines),
            scientificName: draft.scientificName.trimmingCharacters(in: .whitespacesAndNewlines),
            photo: photo,
            wateringIntervalDays: draft.seasonalWatering.summer,
            wateringTrigger: draft.wateringTrigger.trimmingCharacters(in: .whitespacesAndNewlines),
            fertilizingIntervalDays: draft.fertilizingInterval,
            fertilizingNotes: draft.fertilizingNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            lightRequirement: draft.lightRequirement,
            toxicityNote: draft.toxicityNote,
            careNote: draft.careNote.trimmingCharacters(in: .whitespacesAndNewlines),
            seasonalWatering: draft.seasonalWatering,
            identificationConfidence: draft.confidence.rawValue
        )

        let lastWatered: Date?
        switch lastWateredChoice {
        case .unknown: lastWatered = nil
        case .today: lastWatered = .now
        case .anotherDate: lastWatered = lastWateredDate
        }
        plant.lastWatered = lastWatered
        let season = Season.current(hemisphere: settings.hemisphere)
        plant.nextCareCheckDate = CareRecommendationEngine.reminderDate(
            addingDays: lastWatered == nil ? 0 : draft.seasonalWatering.interval(for: season),
            to: lastWatered ?? .now,
            hour: settings.reminderHour,
            minute: settings.reminderMinute
        )
        modelContext.insert(plant)
        if let lastWatered {
            modelContext.insert(CareEvent(kind: .watering, date: lastWatered, plant: plant))
        }

        do {
            try modelContext.save()
            await NotificationService.shared.scheduleSoilCheck(
                for: plant,
                settings: settings.snapshot
            )
            let status = await NotificationService.shared.authorizationStatus()
            if isFirstPlant && status == .notDetermined {
                notificationPrimerPlant = plant
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NotificationPrimerView: View {
    @Environment(AppSettings.self) private var settings
    let plant: Plant
    let finished: () -> Void
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 64))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BotanicalTheme.tint)
                VStack(spacing: 8) {
                    Text("Remember the next soil check")
                        .font(.title2.bold())
                    Text("Plants can remind you when it is time to check \(plant.commonName). It will never tell you to water without checking first.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    Task {
                        isRequesting = true
                        let granted = await NotificationService.shared.requestPermission()
                        if granted {
                            await NotificationService.shared.scheduleSoilCheck(
                                for: plant,
                                settings: settings.snapshot
                            )
                        }
                        isRequesting = false
                        finished()
                    }
                } label: {
                    if isRequesting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Enable Reminders", systemImage: "bell.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(isRequesting)
                Button("Not now", action: finished)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PlantDraft {
    var commonName: String
    var scientificName: String
    var confidence: IdentificationConfidence
    var wateringTrigger: String
    var seasonalWatering: SeasonalWatering
    var fertilizingInterval: Int
    var fertilizingNotes: String
    var lightRequirement: String
    var toxicityNote: String
    var careNote: String

    init(identification: PlantIdentification) {
        commonName = identification.commonName
        scientificName = identification.scientificName
        confidence = identification.confidence
        wateringTrigger = identification.wateringTrigger
        seasonalWatering = identification.seasonalWatering
        fertilizingInterval = identification.fertilizingIntervalDaysGrowingSeason
        fertilizingNotes = identification.fertilizingNotes
        lightRequirement = identification.lightRequirement
        toxicityNote = identification.toxicityNote
        careNote = identification.careNote
    }

}

private enum AddPlantError: LocalizedError {
    case unreadablePhoto

    var errorDescription: String? {
        "That photo could not be read. Try another image."
    }
}
