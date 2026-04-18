import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddPlantView: View {
    enum Step {
        case pickingPhoto
        case identifying(Data)
        case confirming(Data, PlantIdentification)
        case failed(Data, String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var step: Step = .pickingPhoto
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var showingCamera = false
    @State private var currentPhotoData: Data?
    @State private var draft = PlantDraft.empty
    @State private var notificationsChecked = false
    @State private var notificationsEnabled = false
    @State private var saveErrorMessage: String?
    @State private var processingErrorMessage: String?

    #if DEBUG
    private let debugSampleImagePath = ProcessInfo.processInfo.environment["PLANTS_DEBUG_SAMPLE_IMAGE"]
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if notificationsChecked && !notificationsEnabled {
                    Text("Notifications are off. Enable them in Settings to get watering reminders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                switch step {
                case .pickingPhoto:
                    pickingPhotoContent
                case .identifying(let data):
                    identifyingContent(photoData: data)
                case .confirming(_, let result):
                    confirmingContent(result: result)
                case .failed(let data, let message):
                    failedContent(photoData: data, message: message)
                }
            }
            .padding(20)
        }
        .navigationTitle("Add Plant")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await requestNotificationPermissionIfNeeded()
        }
        .onChange(of: selectedPhotoItem, initial: false) { _, newValue in
            guard let newValue else { return }

            Task {
                await loadPhoto(from: newValue)
            }
        }
        .onChange(of: capturedImage, initial: false) { _, newValue in
            guard let newValue else { return }

            processSelectedImage(newValue)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $capturedImage)
        }
        .alert("Could not save plant", isPresented: saveErrorBinding) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
        .alert("Could not use photo", isPresented: processingErrorBinding) {
            Button("OK", role: .cancel) {
                processingErrorMessage = nil
            }
        } message: {
            Text(processingErrorMessage ?? "Unknown error")
        }
    }

    private var pickingPhotoContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                showingCamera = true
            } label: {
                Label("Take photo", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Pick from library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            #if DEBUG
            if debugSampleImagePath != nil {
                Button {
                    useDebugSampleImage()
                } label: {
                    Label("Use sample image", systemImage: "leaf")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func identifyingContent(photoData: Data) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PlantPhotoView(photoData: photoData)
                .frame(maxWidth: .infinity)
                .frame(height: 220)

            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Identifying plant…")
                        .font(.headline)
                    Text("This usually takes a few seconds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func confirmingContent(result: PlantIdentification) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            PlantPhotoView(photoData: currentPhotoData)
                .frame(maxWidth: .infinity)
                .frame(height: 220)

            if result.confidence == "low" {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Confidence is low. Double-check the details below.")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            FormSection(title: "Identity") {
                LabeledField(label: "Common name") {
                    PlainTextField(placeholder: "e.g. Swiss Cheese Plant", text: $draft.commonName)
                }
                LabeledField(label: "Scientific name") {
                    PlainTextField(placeholder: "e.g. Monstera deliciosa", text: $draft.scientificName, italic: true)
                }
            }

            FormSection(title: "Watering") {
                LabeledField(label: "Every") {
                    IntervalStepper(value: $draft.wateringIntervalDays, range: 1...60, unit: "days")
                }
                LabeledField(label: "When") {
                    PlainTextField(
                        placeholder: "e.g. top 2–3 cm of soil feels dry",
                        text: $draft.wateringTrigger,
                        axis: .vertical,
                        lineLimit: 2...4
                    )
                }
            }

            FormSection(title: "Fertilizing") {
                Toggle("Enable fertilizing reminders", isOn: $draft.isFertilizingEnabled)
                    .tint(.green)

                if draft.isFertilizingEnabled {
                    LabeledField(label: "Every") {
                        IntervalStepper(value: $draft.fertilizingIntervalDays, range: 7...120, unit: "days")
                    }
                    LabeledField(label: "Notes") {
                        PlainTextField(
                            placeholder: "e.g. balanced liquid feed in spring and summer",
                            text: $draft.fertilizingNotes,
                            axis: .vertical,
                            lineLimit: 2...4
                        )
                    }
                }
            }

            FormSection(title: "Light") {
                Picker("Light", selection: $draft.lightRequirement) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("Indirect").tag("bright_indirect")
                    Text("Direct").tag("direct_sun")
                }
                .pickerStyle(.segmented)
            }

            FormSection(title: "Notes") {
                LabeledField(label: "Toxicity") {
                    PlainTextField(
                        placeholder: "e.g. mildly toxic to pets if ingested",
                        text: $draft.toxicityNote,
                        axis: .vertical,
                        lineLimit: 2...5
                    )
                }
                LabeledField(label: "Care") {
                    PlainTextField(
                        placeholder: "e.g. wipe leaves; provide a moss pole",
                        text: $draft.careNote,
                        axis: .vertical,
                        lineLimit: 2...5
                    )
                }
            }

            VStack(spacing: 10) {
                Button {
                    Task { await savePlant() }
                } label: {
                    Text("Save plant")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(draft.commonName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    step = .pickingPhoto
                } label: {
                    Text("Use a different photo")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 4)
        }
    }

    private func failedContent(photoData: Data, message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PlantPhotoView(photoData: photoData)
                .frame(maxWidth: .infinity)
                .frame(height: 200)

            Text(message)
                .foregroundStyle(.red)

            HStack(spacing: 12) {
                Button("Try again") {
                    resetToPicking()
                }
                .buttonStyle(.borderedProminent)

                Button("Enter manually") {
                    draft = PlantDraft(identification: .manualFallback)
                    step = .confirming(photoData, .manualFallback)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private var processingErrorBinding: Binding<Bool> {
        Binding(
            get: { processingErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    processingErrorMessage = nil
                }
            }
        )
    }

    private func requestNotificationPermissionIfNeeded() async {
        guard !notificationsChecked else { return }

        let granted = await NotificationService.shared.requestPermissionIfNeeded()
        notificationsEnabled = granted
        notificationsChecked = true
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                processingErrorMessage = "Could not load the selected photo."
                return
            }

            processSelectedImage(image)
        } catch {
            processingErrorMessage = error.localizedDescription
        }
    }

    private func processSelectedImage(_ image: UIImage) {
        guard let processedData = PhotoProcessor.process(image) else {
            processingErrorMessage = "Could not prepare the selected photo."
            return
        }

        currentPhotoData = processedData
        step = .identifying(processedData)

        Task {
            await identifyPlant(using: processedData)
        }
    }

    private func identifyPlant(using photoData: Data) async {
        do {
            let result = try await GeminiClient.shared.identify(imageJPEG: photoData)
            draft = PlantDraft(identification: result)
            step = .confirming(photoData, result)
        } catch {
            step = .failed(photoData, error.localizedDescription)
        }
    }

    private func savePlant() async {
        let plant = Plant(
            commonName: draft.commonName.trimmingCharacters(in: .whitespacesAndNewlines),
            scientificName: draft.scientificName.trimmingCharacters(in: .whitespacesAndNewlines),
            photo: currentPhotoData,
            wateringIntervalDays: draft.wateringIntervalDays,
            wateringTrigger: draft.wateringTrigger.trimmingCharacters(in: .whitespacesAndNewlines),
            fertilizingIntervalDays: draft.isFertilizingEnabled ? draft.fertilizingIntervalDays : 0,
            fertilizingNotes: draft.fertilizingNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            lightRequirement: draft.lightRequirement,
            toxicityNote: draft.toxicityNote.trimmingCharacters(in: .whitespacesAndNewlines),
            careNote: draft.careNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        modelContext.insert(plant)

        do {
            try modelContext.save()

            if notificationsEnabled {
                await NotificationService.shared.scheduleWater(for: plant)
                await NotificationService.shared.scheduleFertilize(for: plant)
            }

            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func resetToPicking() {
        selectedPhotoItem = nil
        capturedImage = nil
        currentPhotoData = nil
        step = .pickingPhoto
    }

    #if DEBUG
    private func useDebugSampleImage() {
        guard let debugSampleImagePath,
              let image = UIImage(contentsOfFile: debugSampleImagePath)
        else {
            processingErrorMessage = "Could not load the sample image."
            return
        }

        processSelectedImage(image)
    }
    #endif
}

private struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct PlainTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>? = nil
    var italic: Bool = false

    var body: some View {
        Group {
            if axis == .vertical {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(lineLimit ?? 1...1)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .italic(italic)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct IntervalStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack(spacing: 14) {
            Button {
                if value > range.lowerBound { value -= 1 }
            } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(value <= range.lowerBound)

            VStack(spacing: 0) {
                Text("\(value)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                if value < range.upperBound { value += 1 }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .disabled(value >= range.upperBound)
        }
    }
}

private struct PlantDraft {
    var commonName: String
    var scientificName: String
    var wateringIntervalDays: Int
    var wateringTrigger: String
    var isFertilizingEnabled: Bool
    var fertilizingIntervalDays: Int
    var fertilizingNotes: String
    var lightRequirement: String
    var toxicityNote: String
    var careNote: String

    static let empty = PlantDraft(identification: .manualFallback)

    init(identification: PlantIdentification) {
        commonName = identification.commonName
        scientificName = identification.scientificName
        wateringIntervalDays = min(max(identification.suggestedWateringInterval, 1), 60)
        wateringTrigger = identification.wateringTrigger
        isFertilizingEnabled = identification.fertilizingIntervalDaysGrowingSeason > 0
        fertilizingIntervalDays = max(identification.fertilizingIntervalDaysGrowingSeason, 7)
        fertilizingNotes = identification.fertilizingNotes
        lightRequirement = identification.lightRequirement
        toxicityNote = identification.toxicityNote
        careNote = identification.careNote
    }
}
