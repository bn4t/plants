import Foundation
import SwiftData
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()

    static let waterCategory = "WATER_REMINDER"
    static let fertilizeCategory = "FERTILIZE_REMINDER"
    static let markWateredAction = "MARK_WATERED"
    static let markFertilizedAction = "MARK_FERTILIZED"

    private var modelContainer: ModelContainer?

    func configureAtLaunch(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let waterAction = UNNotificationAction(
            identifier: Self.markWateredAction,
            title: "Mark as watered",
            options: []
        )
        let fertilizeAction = UNNotificationAction(
            identifier: Self.markFertilizedAction,
            title: "Mark as fertilized",
            options: []
        )
        let waterCategory = UNNotificationCategory(
            identifier: Self.waterCategory,
            actions: [waterAction],
            intentIdentifiers: [],
            options: []
        )
        let fertilizeCategory = UNNotificationCategory(
            identifier: Self.fertilizeCategory,
            actions: [fertilizeAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([waterCategory, fertilizeCategory])
    }

    func requestPermissionIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        @unknown default:
            return false
        }
    }

    @MainActor
    func scheduleWater(for plant: Plant) async {
        await scheduleWater(using: ReminderSnapshot(plant: plant))
    }

    @MainActor
    func scheduleFertilize(for plant: Plant) async {
        await scheduleFertilize(using: ReminderSnapshot(plant: plant))
    }

    func cancelAll(for plantID: UUID) {
        cancel(id: waterID(for: plantID))
        cancel(id: fertilizeID(for: plantID))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let plantIDString = userInfo["plantId"] as? String,
              let plantID = UUID(uuidString: plantIDString)
        else {
            return
        }

        switch response.actionIdentifier {
        case Self.markWateredAction:
            await applyAction(.water, to: plantID)
        case Self.markFertilizedAction:
            await applyAction(.fertilize, to: plantID)
        default:
            NotificationCenter.default.post(
                name: .plantNotificationOpened,
                object: nil,
                userInfo: ["plantId": plantID]
            )
        }
    }

    private func schedule(
        id: String,
        category: String,
        title: String,
        body: String,
        userInfo: [String: Any],
        fireAt: Date
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = userInfo

        let interval = max(fireAt.timeIntervalSinceNow, 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    private func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func waterID(for plantID: UUID) -> String {
        "\(plantID.uuidString)-water"
    }

    private func fertilizeID(for plantID: UUID) -> String {
        "\(plantID.uuidString)-fertilize"
    }

    private func applyAction(_ action: PlantAction, to plantID: UUID) async {
        guard let modelContainer else { return }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Plant>(predicate: #Predicate<Plant> { plant in
            plant.id == plantID
        })

        do {
            guard let plant = try context.fetch(descriptor).first else { return }
            let snapshot = ReminderSnapshot(plant: plant)

            switch action {
            case .water:
                plant.lastWatered = .now
                try context.save()
                await scheduleWater(using: snapshot.updating(nextWateringDate: plant.nextWateringDate))
            case .fertilize:
                plant.lastFertilized = .now
                try context.save()
                await scheduleFertilize(using: snapshot.updating(nextFertilizingDate: plant.nextFertilizingDate))
            }
        } catch {
            print("Failed to apply plant action: \(error.localizedDescription)")
        }
    }

    private enum PlantAction {
        case water
        case fertilize
    }

    private struct ReminderSnapshot: Sendable {
        let id: UUID
        let commonName: String
        let wateringTrigger: String
        let nextWateringDate: Date
        let fertilizingNotes: String
        let nextFertilizingDate: Date?

        init(plant: Plant) {
            id = plant.id
            commonName = plant.commonName
            wateringTrigger = plant.wateringTrigger
            nextWateringDate = plant.nextWateringDate
            fertilizingNotes = plant.fertilizingNotes
            nextFertilizingDate = plant.nextFertilizingDate
        }

        func updating(nextWateringDate: Date? = nil, nextFertilizingDate: Date? = nil) -> ReminderSnapshot {
            ReminderSnapshot(
                id: id,
                commonName: commonName,
                wateringTrigger: wateringTrigger,
                nextWateringDate: nextWateringDate ?? self.nextWateringDate,
                fertilizingNotes: fertilizingNotes,
                nextFertilizingDate: nextFertilizingDate ?? self.nextFertilizingDate
            )
        }

        private init(
            id: UUID,
            commonName: String,
            wateringTrigger: String,
            nextWateringDate: Date,
            fertilizingNotes: String,
            nextFertilizingDate: Date?
        ) {
            self.id = id
            self.commonName = commonName
            self.wateringTrigger = wateringTrigger
            self.nextWateringDate = nextWateringDate
            self.fertilizingNotes = fertilizingNotes
            self.nextFertilizingDate = nextFertilizingDate
        }
    }

    private func scheduleWater(using snapshot: ReminderSnapshot) async {
        await schedule(
            id: waterID(for: snapshot.id),
            category: Self.waterCategory,
            title: "Time to water \(snapshot.commonName)",
            body: snapshot.wateringTrigger.isEmpty
                ? "Tap to mark as watered."
                : "\(snapshot.wateringTrigger). Tap to mark as watered.",
            userInfo: ["plantId": snapshot.id.uuidString, "type": "water"],
            fireAt: snapshot.nextWateringDate
        )
    }

    private func scheduleFertilize(using snapshot: ReminderSnapshot) async {
        guard let next = snapshot.nextFertilizingDate else {
            cancel(id: fertilizeID(for: snapshot.id))
            return
        }

        await schedule(
            id: fertilizeID(for: snapshot.id),
            category: Self.fertilizeCategory,
            title: "Time to fertilize \(snapshot.commonName)",
            body: snapshot.fertilizingNotes.isEmpty
                ? "Tap to mark as fertilized."
                : "\(snapshot.fertilizingNotes). Tap to mark as fertilized.",
            userInfo: ["plantId": snapshot.id.uuidString, "type": "fertilize"],
            fireAt: next
        )
    }
}

extension Notification.Name {
    static let plantNotificationOpened = Notification.Name("plantNotificationOpened")
}
