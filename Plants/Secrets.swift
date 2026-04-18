import Foundation

enum Secrets {
    static let userDefaultsKey = "openRouterAPIKey"

    static var openRouterAPIKey: String? {
        guard let value = UserDefaults.standard.string(forKey: userDefaultsKey),
              !value.trimmingCharacters(in: .whitespaces).isEmpty
        else {
            return nil
        }
        return value
    }

    static func setOpenRouterAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        }
    }
}
