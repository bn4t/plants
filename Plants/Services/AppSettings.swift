import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppSettingsSnapshot: Sendable {
    let hemisphere: Hemisphere
    let reminderHour: Int
    let reminderMinute: Int
    let hapticsEnabled: Bool
}

@MainActor
@Observable
final class AppSettings {
    static let hemisphereKey = "hemisphere"
    static let reminderHourKey = "reminderHour"
    static let reminderMinuteKey = "reminderMinute"
    static let hapticsKey = "hapticsEnabled"
    static let appearanceKey = "appearance"

    var hemisphere: Hemisphere {
        didSet { defaults.set(hemisphere.rawValue, forKey: Self.hemisphereKey) }
    }

    var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: Self.reminderHourKey) }
    }

    var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: Self.reminderMinuteKey) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }

    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hemisphere = Hemisphere(
            rawValue: defaults.string(forKey: Self.hemisphereKey) ?? Hemisphere.northern.rawValue
        ) ?? .northern
        reminderHour = defaults.object(forKey: Self.reminderHourKey) == nil
            ? 9
            : defaults.integer(forKey: Self.reminderHourKey)
        reminderMinute = defaults.integer(forKey: Self.reminderMinuteKey)
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) == nil
            ? true
            : defaults.bool(forKey: Self.hapticsKey)
        appearance = AppAppearance(
            rawValue: defaults.string(forKey: Self.appearanceKey) ?? AppAppearance.system.rawValue
        ) ?? .system
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            hemisphere: hemisphere,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            hapticsEnabled: hapticsEnabled
        )
    }
}
