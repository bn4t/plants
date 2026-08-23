import AuthenticationServices
import XCTest
@testable import Plants

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class GeminiAndOAuthTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testGeminiRequestUsesCurrentModelAndStrictStructuredOutput() async throws {
        let client = GeminiClient(session: makeSession(), apiKeyOverride: "test-key", retryDelay: .zero)
        let request = try await client.makeRequest(
            imageJPEG: Data([0x01, 0x02]),
            apiKey: "test-key",
            hemisphere: .northern,
            date: Date(timeIntervalSince1970: 0)
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let responseFormat = try XCTUnwrap(json["response_format"] as? [String: Any])
        let reasoning = try XCTUnwrap(json["reasoning"] as? [String: Any])
        let provider = try XCTUnwrap(json["provider"] as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "google/gemini-3.7-flash")
        XCTAssertEqual(responseFormat["type"] as? String, "json_schema")
        XCTAssertEqual(reasoning["effort"] as? String, "low")
        XCTAssertEqual(reasoning["exclude"] as? Bool, true)
        XCTAssertEqual(provider["require_parameters"] as? Bool, true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://github.com/bn4t/plants")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Plants for iOS")
    }

    func testGeminiDecodingClampsNumericRanges() async throws {
        StubURLProtocol.handler = { request in
            (Self.response(for: request, status: 200), try Self.openRouterBody(
                confidence: "high",
                spring: 0,
                summer: 200,
                autumn: 9,
                winter: 12,
                fertilizer: 500
            ))
        }
        let client = GeminiClient(session: makeSession(), apiKeyOverride: "test-key", retryDelay: .zero)

        let result = try await client.identify(imageJPEG: Data([0x01]), hemisphere: .northern)

        XCTAssertEqual(result.wateringIntervalSpring, 1)
        XCTAssertEqual(result.wateringIntervalSummer, 60)
        XCTAssertEqual(result.fertilizingIntervalDaysGrowingSeason, 120)
        XCTAssertEqual(result.commonName, "Swiss Cheese Plant")
    }

    func testUncertainIdentificationRemainsExplicitlyLowConfidence() async throws {
        StubURLProtocol.handler = { request in
            (Self.response(for: request, status: 200), try Self.openRouterBody(confidence: "low"))
        }
        let client = GeminiClient(session: makeSession(), apiKeyOverride: "test-key", retryDelay: .zero)

        let result = try await client.identify(imageJPEG: Data([0x01]), hemisphere: .northern)

        XCTAssertEqual(result.confidence, .low)
    }

    func testMalformedResponseIsRejected() async throws {
        StubURLProtocol.handler = { request in
            let body = try JSONSerialization.data(withJSONObject: [
                "choices": [["message": ["content": "not-json"]]]
            ])
            return (Self.response(for: request, status: 200), body)
        }
        let client = GeminiClient(session: makeSession(), apiKeyOverride: "test-key", retryDelay: .zero)

        do {
            _ = try await client.identify(imageJPEG: Data([0x01]), hemisphere: .northern)
            XCTFail("Expected malformed response to fail")
        } catch GeminiError.decodingFailure {
            XCTAssertTrue(true)
        }
    }

    func testOfflineRequestReturnsNetworkFailure() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let client = GeminiClient(session: makeSession(), apiKeyOverride: "test-key", retryDelay: .zero)

        do {
            _ = try await client.identify(imageJPEG: Data([0x01]), hemisphere: .northern)
            XCTFail("Expected offline failure")
        } catch GeminiError.networkFailure {
            XCTAssertTrue(true)
        }
    }

    func testRateLimitRetriesOnce() async throws {
        var attempt = 0
        StubURLProtocol.handler = { request in
            attempt += 1
            if attempt == 1 {
                return (Self.response(for: request, status: 429), Data())
            }
            return (Self.response(for: request, status: 200), try Self.openRouterBody())
        }
        let client = GeminiClient(session: makeSession(), apiKeyOverride: "test-key", retryDelay: .zero)

        _ = try await client.identify(imageJPEG: Data([0x01]), hemisphere: .northern)

        XCTAssertEqual(attempt, 2)
    }

    func testPKCEUsesS256AndHTTPSCallbackMatcher() throws {
        let verifier = OpenRouterAuthService.makeCodeVerifier()
        XCTAssertEqual(verifier.count, 43)
        XCTAssertNotNil(verifier.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression))
        XCTAssertEqual(
            OpenRouterAuthService.codeChallenge(
                for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
            ),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )

        let callback = ASWebAuthenticationSession.Callback.https(
            host: "github.com",
            path: "/bn4t/plants"
        )
        XCTAssertTrue(callback.matchesURL(URL(string: "https://github.com/bn4t/plants?code=test")!))

        let authURL = try OpenRouterAuthService.authorizationURL(codeChallenge: "challenge")
        let components = try XCTUnwrap(URLComponents(url: authURL, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(values["callback_url"]!, "https://github.com/bn4t/plants")
        XCTAssertEqual(values["code_challenge_method"]!, "S256")
    }

    func testOAuthConnectedFlowExchangesValidatesAndStoresKey() async throws {
        var storedKey: String?
        StubURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/api/v1/auth/keys")
                return (Self.response(for: request, status: 200), Data(#"{"key":"test-user-key"}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-user-key")
            return (Self.response(for: request, status: 200), Data(#"{"data":{}}"#.utf8))
        }
        let service = OpenRouterAuthService(
            urlSession: makeSession(),
            authenticator: { authorizationURL in
                XCTAssertEqual(authorizationURL.host, "openrouter.ai")
                return URL(string: "https://github.com/bn4t/plants?code=authorization-code")!
            },
            saveKey: { storedKey = $0 }
        )

        try await service.connect()

        XCTAssertEqual(storedKey, "test-user-key")
    }

    func testOAuthCancellationIsPreserved() async throws {
        let service = OpenRouterAuthService(
            urlSession: makeSession(),
            authenticator: { _ in throw OpenRouterConnectionError.cancelled },
            saveKey: { _ in XCTFail("Cancelled OAuth must not save a key") }
        )

        do {
            try await service.connect()
            XCTFail("Expected cancellation")
        } catch OpenRouterConnectionError.cancelled {
            XCTAssertTrue(true)
        }
    }

    func testLocalOAuthCallbackReceivesCodeWithoutCopyPaste() async throws {
        let server = LocalOAuthCallbackServer()
        let callbackURL = try await server.start()
        defer { server.stop() }
        let callbackTask = Task { try await server.waitForCallback() }
        var components = try XCTUnwrap(URLComponents(url: callbackURL, resolvingAgainstBaseURL: false))
        components.queryItems = [URLQueryItem(name: "code", value: "local-code")]
        let requestURL = try XCTUnwrap(components.url)

        let (_, response) = try await URLSession.shared.data(from: requestURL)
        let receivedURL = try await callbackTask.value

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(
            URLComponents(url: receivedURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value,
            "local-code"
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated private static func response(for request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    nonisolated private static func openRouterBody(
        confidence: String = "high",
        spring: Int = 8,
        summer: Int = 7,
        autumn: Int = 10,
        winter: Int = 14,
        fertilizer: Int = 30
    ) throws -> Data {
        let identification: [String: Any] = [
            "scientific_name": "Monstera deliciosa",
            "common_name": "Swiss Cheese Plant",
            "confidence": confidence,
            "watering_trigger": "Water when the top 3 cm are dry",
            "watering_interval_spring": spring,
            "watering_interval_summer": summer,
            "watering_interval_autumn": autumn,
            "watering_interval_winter": winter,
            "fertilizing_interval_days_growing_season": fertilizer,
            "fertilizing_notes": "Feed moist potting mix and follow the product label",
            "light_requirement": "bright_indirect",
            "toxicity_note": "Keep away from pets",
            "care_note": "Provide climbing support"
        ]
        let contentData = try JSONSerialization.data(withJSONObject: identification)
        let content = String(decoding: contentData, as: UTF8.self)
        return try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]]
        ])
    }
}
