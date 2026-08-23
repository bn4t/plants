import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum OpenRouterConnectionError: LocalizedError {
    case couldNotStart
    case cancelled
    case callbackServerFailed
    case missingCode
    case invalidResponse
    case rejected(Int)

    var errorDescription: String? {
        switch self {
        case .couldNotStart: "Could not open OpenRouter sign-in."
        case .cancelled: "OpenRouter sign-in was cancelled."
        case .callbackServerFailed: "Could not receive the secure sign-in callback on this device."
        case .missingCode: "OpenRouter did not return an authorization code."
        case .invalidResponse: "OpenRouter returned an unreadable response."
        case .rejected(let status): "OpenRouter rejected the connection (HTTP \(status))."
        }
    }
}

@MainActor
final class OpenRouterAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let publicProjectURL = URL(string: "https://github.com/bn4t/plants")!

    private var webSession: ASWebAuthenticationSession?
    private let urlSession: URLSession
    private let authenticator: ((URL) async throws -> URL)?
    private let saveKey: (String) throws -> Void

    init(
        urlSession: URLSession = .shared,
        authenticator: ((URL) async throws -> URL)? = nil,
        saveKey: @escaping (String) throws -> Void = { try Secrets.setOpenRouterAPIKey($0) }
    ) {
        self.urlSession = urlSession
        self.authenticator = authenticator
        self.saveKey = saveKey
    }

    func connect() async throws {
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let callbackURL: URL
        if let authenticator {
            let authorizationURL = try Self.authorizationURL(
                codeChallenge: challenge,
                callbackURL: Self.publicProjectURL
            )
            callbackURL = try await authenticator(authorizationURL)
        } else {
            callbackURL = try await authenticateUsingLocalCallback(codeChallenge: challenge)
        }
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value,
            !code.isEmpty
        else {
            throw OpenRouterConnectionError.missingCode
        }

        let key = try await exchange(code: code, verifier: verifier)
        try await validate(key: key)
        try saveKey(key)
    }

    func validateStoredKey() async -> Bool {
        guard let key = Secrets.openRouterAPIKey else { return false }
        do {
            try await validate(key: key)
            return true
        } catch {
            return false
        }
    }

    func validateAndStore(key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OpenRouterConnectionError.invalidResponse
        }
        try await validate(key: trimmed)
        try saveKey(trimmed)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return window
        }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else {
            preconditionFailure("OpenRouter sign-in requires an active window scene")
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }

    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure random generation failed")
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    static func authorizationURL(
        codeChallenge: String,
        callbackURL: URL = publicProjectURL
    ) throws -> URL {
        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "key_label", value: "Plants for iOS")
        ]
        guard let url = components.url else {
            throw OpenRouterConnectionError.invalidResponse
        }
        return url
    }

    private func authenticateUsingLocalCallback(codeChallenge: String) async throws -> URL {
        let callbackServer = LocalOAuthCallbackServer()
        let callbackURL = try await callbackServer.start()
        let authorizationURL = try Self.authorizationURL(
            codeChallenge: codeChallenge,
            callbackURL: callbackURL
        )
        defer {
            callbackServer.stop()
            webSession?.cancel()
            webSession = nil
        }

        let session = ASWebAuthenticationSession(
            url: authorizationURL,
            callback: .customScheme("plants")
        ) { [weak self, callbackServer] _, error in
            Task { @MainActor in self?.webSession = nil }
            if let authError = error as? ASWebAuthenticationSessionError,
               authError.code == .canceledLogin {
                callbackServer.fail(with: OpenRouterConnectionError.cancelled)
            } else if let error {
                callbackServer.fail(with: error)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webSession = session
        guard session.start() else {
            throw OpenRouterConnectionError.couldNotStart
        }
        return try await callbackServer.waitForCallback()
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            CodeExchangeRequest(
                code: code,
                codeVerifier: verifier,
                codeChallengeMethod: "S256"
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OpenRouterConnectionError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenRouterConnectionError.rejected(response.statusCode)
        }
        guard let key = try? JSONDecoder().decode(CodeExchangeResponse.self, from: data).key,
              !key.isEmpty
        else {
            throw OpenRouterConnectionError.invalidResponse
        }
        return key
    }

    private func validate(key: String) async throws {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OpenRouterConnectionError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenRouterConnectionError.rejected(response.statusCode)
        }
    }

    private struct CodeExchangeRequest: Encodable {
        let code: String
        let codeVerifier: String
        let codeChallengeMethod: String
    }

    private struct CodeExchangeResponse: Decodable {
        let key: String
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
