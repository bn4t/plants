import SwiftData
import SwiftUI
import UIKit
import UserNotifications

private enum OpenRouterConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case checking
    case problem(String)

    var title: String {
        switch self {
        case .disconnected: "Not connected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .checking: "Checking"
        case .problem: "Needs attention"
        }
    }

    var systemImage: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .connecting, .checking: "arrow.trianglehead.2.clockwise.rotate.90"
        case .disconnected: "person.crop.circle.badge.plus"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .connected: .green
        case .problem: .orange
        case .connecting, .checking: BotanicalTheme.tint
        case .disconnected: .secondary
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Plant.createdAt) private var plants: [Plant]

    @State private var connectionState: OpenRouterConnectionState = .disconnected
    @State private var manualKey = ""
    @State private var showingAdvancedKey = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isWorking = false
    @State private var message: (title: String, text: String)?
    @State private var reminderRescheduleTask: Task<Void, Never>?
    @State private var showingDeleteConfirmation = false
    @State private var authService = OpenRouterAuthService()

    var body: some View {
        Form {
            remindersSection
            environmentSection
            appearanceSection
            openRouterSection
            dataSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                .fontWeight(.semibold)
            }
        }
        .task {
            connectionState = Secrets.hasOpenRouterAPIKey ? .connected : .disconnected
            await refreshNotificationStatus()
        }
        .alert(message?.title ?? "Something Went Wrong", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message?.text ?? "")
        }
        .alert("Delete all local plant data?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteAllPlantData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every plant, photo, and care-history entry from this device. Your OpenRouter connection is kept.")
        }
    }

    private var openRouterSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: connectionState.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(connectionState.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionState.title)
                        .font(.body.weight(.medium))
                    if case .problem(let detail) = connectionState {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Plant identification through OpenRouter")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if connectionState == .connected {
                Button {
                    Task { await connect() }
                } label: {
                    Label("Reconnect OpenRouter", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .disabled(isWorking)

                Button {
                    Task { await checkConnection() }
                } label: {
                    Label("Check Connection", systemImage: "checkmark.shield")
                }
                .disabled(isWorking)

                if let manageURL = Secrets.openRouterKeySettingsURL {
                    Link(destination: manageURL) {
                        Label("Manage on OpenRouter", systemImage: "arrow.up.right.square")
                    }
                }

                Button(role: .destructive, action: disconnect) {
                    Label("Disconnect", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Label("Connect OpenRouter", systemImage: "person.crop.circle.badge.checkmark")
                        Spacer()
                        if isWorking { ProgressView() }
                    }
                }
                .disabled(isWorking)
            }

            DisclosureGroup("Advanced", isExpanded: $showingAdvancedKey) {
                SecureField("OpenRouter key", text: $manualKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()

                Button {
                    Task { await saveManualKey() }
                } label: {
                    Label("Validate and Save Key", systemImage: "key.fill")
                }
                .disabled(manualKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }
        } header: {
            Text("Plant identification")
        } footer: {
            Text("Connect opens a private system sign-in session. The resulting key is validated, stored in this device's Keychain, and never displayed in full.")
        }
    }

    private var remindersSection: some View {
        Section("Reminders") {
            HStack {
                Label("Notifications", systemImage: notificationSymbol)
                Spacer()
                Text(notificationStatusText)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            DatePicker(
                "Reminder time",
                selection: reminderTimeBinding,
                displayedComponents: .hourAndMinute
            )

            switch notificationStatus {
            case .notDetermined:
                Button {
                    Task {
                        _ = await NotificationService.shared.requestPermission()
                        await refreshNotificationStatus()
                        await rescheduleAll()
                    }
                } label: {
                    Label("Enable Reminders", systemImage: "bell.badge.fill")
                }
            case .denied:
                Button(action: openSystemSettings) {
                    Label("Open iOS Settings", systemImage: "gear")
                }
            case .authorized, .provisional, .ephemeral:
                Button {
                    Task {
                        do {
                            try await NotificationService.shared.scheduleTestNotification()
                            message = (
                                title: "Test Reminder Scheduled",
                                text: "A test soil-check reminder will arrive in five seconds."
                            )
                        } catch {
                            message = (
                                title: "Something Went Wrong",
                                text: error.localizedDescription
                            )
                        }
                    }
                } label: {
                    Label("Send Test Reminder", systemImage: "bell.and.waves.left.and.right")
                }
            @unknown default:
                EmptyView()
            }
        }
    }

    private var environmentSection: some View {
        Section {
            Picker("Hemisphere", selection: hemisphereBinding) {
                ForEach(Hemisphere.allCases, id: \.self) { hemisphere in
                    Text(hemisphere.displayName).tag(hemisphere)
                }
            }

            SeasonStrip(
                current: Season.current(hemisphere: settings.hemisphere),
                intervals: nil
            )
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            Label(
                Season.current(hemisphere: settings.hemisphere).indoorNote,
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("Season")
        } footer: {
            Text("Season sets the initial species baseline only. Logged watering cycles and damp-soil checks adapt timing to your actual room, pot, and potting mix.")
        }
    }

    private var appearanceSection: some View {
        Section("Appearance and accessibility") {
            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            Toggle(isOn: hapticsBinding) {
                Label("Success haptics", systemImage: "hand.tap")
            }
        }
    }

    private var dataSection: some View {
        Section("Data recovery") {
            Button {
                Task {
                    await rescheduleAll()
                    message = (
                        title: "Reminders Rebuilt",
                        text: "Soil-check reminders were rebuilt from your saved care plans."
                    )
                }
            } label: {
                Label("Rebuild Reminders", systemImage: "arrow.clockwise")
            }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete All Plant Data", systemImage: "trash")
            }
            .disabled(plants.isEmpty)
        }
    }

    private var aboutSection: some View {
        Section("About care guidance") {
            Label("Always check the potting mix before watering.", systemImage: "drop.degreesign")
            Label("Feed only during active growth and when the potting mix is moist. Follow the product label for dosage.", systemImage: "leaf.fill")
            Label("Verify toxicity guidance with a veterinarian if a pet may have eaten a plant.", systemImage: "cross.case")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var hemisphereBinding: Binding<Hemisphere> {
        Binding(get: { settings.hemisphere }, set: { settings.hemisphere = $0 })
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(get: { settings.appearance }, set: { settings.appearance = $0 })
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(get: { settings.hapticsEnabled }, set: { settings.hapticsEnabled = $0 })
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.reminderHour,
                    minute: settings.reminderMinute,
                    second: 0,
                    of: Date.now
                ) ?? Date.now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.reminderHour = components.hour ?? 9
                settings.reminderMinute = components.minute ?? 0
                scheduleReminderReschedule()
            }
        )
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .notDetermined: "Not set"
        case .denied: "Off"
        case .authorized, .provisional, .ephemeral: "On"
        @unknown default: "Unknown"
        }
    }

    private var notificationSymbol: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "bell.badge.fill"
        case .denied: "bell.slash.fill"
        default: "bell"
        }
    }

    private func connect() async {
        isWorking = true
        connectionState = .connecting
        defer { isWorking = false }
        do {
            try await authService.connect()
            connectionState = .connected
        } catch OpenRouterConnectionError.cancelled {
            connectionState = Secrets.hasOpenRouterAPIKey ? .connected : .disconnected
        } catch {
            connectionState = .problem(error.localizedDescription)
        }
    }

    private func checkConnection() async {
        isWorking = true
        connectionState = .checking
        let isValid = await authService.validateStoredKey()
        connectionState = isValid
            ? .connected
            : .problem("The saved key could not be validated. Check your connection or reconnect.")
        isWorking = false
    }

    private func saveManualKey() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await authService.validateAndStore(key: manualKey)
            manualKey = ""
            showingAdvancedKey = false
            connectionState = .connected
        } catch {
            connectionState = .problem(error.localizedDescription)
        }
    }

    private func disconnect() {
        do {
            try Secrets.clearOpenRouterAPIKey()
            connectionState = .disconnected
            manualKey = ""
        } catch {
            message = (
                title: "Something Went Wrong",
                text: error.localizedDescription
            )
        }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.shared.authorizationStatus()
    }

    private func rescheduleAll() async {
        await NotificationService.shared.rescheduleAll(
            for: plants,
            settings: settings.snapshot
        )
    }

    private func scheduleReminderReschedule() {
        reminderRescheduleTask?.cancel()
        reminderRescheduleTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await rescheduleAll()
        }
    }

    private func deleteAllPlantData() {
        do {
            for plant in plants { modelContext.delete(plant) }
            try modelContext.save()
            NotificationService.shared.cancelAllNotifications()
            message = (
                title: "Plant Data Deleted",
                text: "All local plant data was deleted."
            )
        } catch {
            message = (
                title: "Something Went Wrong",
                text: error.localizedDescription
            )
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
