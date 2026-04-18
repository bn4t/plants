import Foundation

enum Secrets {
    static var openRouterAPIKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENROUTER_API_KEY") as? String,
              !key.isEmpty
        else {
            fatalError("OPENROUTER_API_KEY missing from Info.plist / Secrets.xcconfig")
        }

        return key
    }
}
