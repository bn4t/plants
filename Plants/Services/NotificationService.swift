import Foundation
import SwiftData
import UIKit
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()

    static let soilCheckCategory = "SOIL_CHECK_REMINDER"
    static let dryAndWateredAction = "DRY_AND_WATERED"
    static let stillDampAction = "STILL_DAMP"
    static let remindTomorrowAction = "REMIND_TOMORROW"

    private var modelContainer: ModelContainer?

    /// Plant tapped open from a notification before the UI subscribed to
    /// `plantNotificationOpened`; consumed by the shell once it appears.
    @MainActor private(set) var pendingOpenedPlantID: UUID?

    @MainActor
    func consumePendingOpenedPlantID() -> UUID? {
        defer { pendingOpenedPlantID = nil }
        return pendingOpenedPlantID
    }

    @MainActor
    func configureAtLaunch(modelContainer: ModelContainer?) {
        if let modelContainer {
            self.modelContainer = modelContainer
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let dry = UNNotificationAction(
            identifier: Self.dryAndWateredAction,
            title: "Dry, watered",
            options: [.foreground]
        )
        let damp = UNNotificationAction(
            identifier: Self.stillDampAction,
            title: "Still damp",
            options: [.foreground]
        )
        let tomorrow = UNNotificationAction(
            identifier: Self.remindTomorrowAction,
            title: "Remind tomorrow",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.soilCheckCategory,
                actions: [dry, damp, tomorrow],
                intentIdentifiers: [],
                options: []
            )
        ])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestPermission() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )) ?? false
        @unknown default:
            return false
        }
    }

    @MainActor
    func scheduleSoilCheck(
        for plant: Plant,
        settings: AppSettingsSnapshot,
        now: Date = .now
    ) async {
        await schedule(snapshot: ReminderSnapshot(plant: plant), settings: settings, now: now)
    }

    @MainActor
    func rescheduleAll(
        for plants: [Plant],
        settings: AppSettingsSnapshot,
        now: Date = .now
    ) async {
        for plant in plants {
            await schedule(snapshot: ReminderSnapshot(plant: plant), settings: settings, now: now)
        }
    }

    func cancel(for plantID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier(for: plantID)]
        )
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func scheduleTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Check your plant's soil"
        content.body = "Water only if the potting mix has reached the recommended dryness."
        content.sound = .default
        content.categoryIdentifier = Self.soilCheckCategory
        let request = UNNotificationRequest(
            identifier: "test-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
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
        guard let idString = userInfo["plantId"] as? String,
              let plantID = UUID(uuidString: idString)
        else {
            return
        }

        switch response.actionIdentifier {
        case Self.dryAndWateredAction:
            await apply(.dryAndWatered, to: plantID)
        case Self.stillDampAction:
            await apply(.stillDamp, to: plantID)
        case Self.remindTomorrowAction:
            await apply(.remindTomorrow, to: plantID)
        case UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                // A cold-start tap can land before the shell subscribes —
                // buffer the target so it is applied once the UI is ready.
                pendingOpenedPlantID = plantID
                NotificationCenter.default.post(
                    name: .plantNotificationOpened,
                    object: nil,
                    userInfo: ["plantId": plantID]
                )
            }
        case UNNotificationDismissActionIdentifier:
            break
        default:
            break
        }
    }

    private func schedule(
        snapshot: ReminderSnapshot,
        settings: AppSettingsSnapshot,
        now: Date
    ) async {
        let id = Self.notificationIdentifier(for: snapshot.id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let dueDate = snapshot.nextCareCheckDate, dueDate > now else {
            return
        }

        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day], from: dueDate)
        components.hour = settings.reminderHour
        components.minute = settings.reminderMinute

        let content = UNMutableNotificationContent()
        content.title = "Check \(snapshot.commonName)'s soil"
        content.body = snapshot.wateringTrigger
        content.sound = .default
        content.categoryIdentifier = Self.soilCheckCategory
        content.interruptionLevel = .active
        content.userInfo = ["plantId": snapshot.id.uuidString]

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: id,
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            )
        } catch {
            // Scheduling can legitimately fail when notifications are denied.
        }
    }

    @MainActor
    private func apply(_ outcome: CareCheckOutcome, to plantID: UUID) async {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<Plant>(predicate: #Predicate<Plant> { $0.id == plantID })
        guard let plant = try? context.fetch(descriptor).first else { return }
        let settings = AppSettings().snapshot
        guard let receipt = try? await PlantCareActions.apply(
            outcome,
            to: plant,
            settings: settings,
            context: context
        ) else { return }
        NotificationCenter.default.post(
            name: .plantCareActionCompleted,
            object: receipt,
            userInfo: ["plantId": plantID]
        )
    }

    static func notificationIdentifier(for plantID: UUID) -> String {
        "\(plantID.uuidString)-soil-check"
    }

    private struct ReminderSnapshot: Sendable {
        let id: UUID
        let commonName: String
        let wateringTrigger: String
        let nextCareCheckDate: Date?

        @MainActor
        init(plant: Plant) {
            id = plant.id
            commonName = plant.commonName.isEmpty ? "your plant" : plant.commonName
            wateringTrigger = plant.soilCheckGuidance
            nextCareCheckDate = plant.nextCareCheckDate
        }
    }
}

extension Notification.Name {
    static let plantNotificationOpened = Notification.Name("plantNotificationOpened")
    static let plantCareActionCompleted = Notification.Name("plantCareActionCompleted")
}
