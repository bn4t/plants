import Foundation

enum OpenRouterModel {
    static let plantIdentification = "google/gemini-3.7-flash"
}

enum IdentificationConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
}

struct PlantIdentification: Codable, Equatable, Sendable {
    let scientificName: String
    let commonName: String
    let confidence: IdentificationConfidence
    let wateringTrigger: String
    let wateringIntervalSpring: Int
    let wateringIntervalSummer: Int
    let wateringIntervalAutumn: Int
    let wateringIntervalWinter: Int
    let fertilizingIntervalDaysGrowingSeason: Int
    let fertilizingNotes: String
    let lightRequirement: String
    let toxicityNote: String
    let careNote: String

    var seasonalWatering: SeasonalWatering {
        SeasonalWatering(
            spring: wateringIntervalSpring,
            summer: wateringIntervalSummer,
            autumn: wateringIntervalAutumn,
            winter: wateringIntervalWinter
        ).clamped
    }

    var normalized: PlantIdentification {
        PlantIdentification(
            scientificName: scientificName.trimmingCharacters(in: .whitespacesAndNewlines),
            commonName: commonName.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: confidence,
            wateringTrigger: wateringTrigger.trimmingCharacters(in: .whitespacesAndNewlines),
            wateringIntervalSpring: wateringIntervalSpring.clamped(to: 1...60),
            wateringIntervalSummer: wateringIntervalSummer.clamped(to: 1...60),
            wateringIntervalAutumn: wateringIntervalAutumn.clamped(to: 1...60),
            wateringIntervalWinter: wateringIntervalWinter.clamped(to: 1...60),
            fertilizingIntervalDaysGrowingSeason: fertilizingIntervalDaysGrowingSeason.clamped(to: 0...120),
            fertilizingNotes: fertilizingNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            lightRequirement: lightRequirement,
            toxicityNote: toxicityNote.trimmingCharacters(in: .whitespacesAndNewlines),
            careNote: careNote.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static let manualFallback = PlantIdentification(
        scientificName: "",
        commonName: "",
        confidence: .low,
        wateringTrigger: "Water when the potting mix reaches the species-appropriate dryness",
        wateringIntervalSpring: 7,
        wateringIntervalSummer: 7,
        wateringIntervalAutumn: 7,
        wateringIntervalWinter: 7,
        fertilizingIntervalDaysGrowingSeason: 0,
        fertilizingNotes: "Feed only while actively growing and follow the product label",
        lightRequirement: "medium",
        toxicityNote: "",
        careNote: "Check the potting mix before every watering"
    )
}

enum GeminiError: Error, LocalizedError {
    case missingAPIKey
    case networkFailure
    case rateLimited
    case badStatus(Int)
    case emptyResponse
    case decodingFailure
    case invalidIdentification

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Connect OpenRouter to identify a plant, or enter its details manually."
        case .networkFailure: "Could not reach the identification service. Check your connection and try again."
        case .rateLimited: "OpenRouter is busy or your limit was reached. Try again shortly."
        case .badStatus(let status): "Plant identification failed (HTTP \(status))."
        case .emptyResponse: "No identification was returned. Try a clearer photo."
        case .decodingFailure: "The identification response could not be read."
        case .invalidIdentification: "The photo did not produce a usable plant identification."
        }
    }
}

actor GeminiClient {
    static let shared = GeminiClient()

    private let session: URLSession
    private let apiKeyOverride: String?
    private let retryDelay: Duration

    init(
        session: URLSession = .shared,
        apiKeyOverride: String? = nil,
        retryDelay: Duration = .seconds(1)
    ) {
        self.session = session
        self.apiKeyOverride = apiKeyOverride
        self.retryDelay = retryDelay
    }

    func identify(
        imageJPEG: Data,
        hemisphere: Hemisphere,
        date: Date = .now
    ) async throws -> PlantIdentification {
        guard let apiKey = apiKeyOverride ?? Secrets.openRouterAPIKey else {
            throw GeminiError.missingAPIKey
        }

        let request = try makeRequest(
            imageJPEG: imageJPEG,
            apiKey: apiKey,
            hemisphere: hemisphere,
            date: date
        )

        for attempt in 0...1 {
            do {
                return try await perform(request)
            } catch GeminiError.rateLimited where attempt == 0 {
                try await Task.sleep(for: retryDelay)
            } catch GeminiError.badStatus(let status) where attempt == 0 && status >= 500 {
                try await Task.sleep(for: retryDelay)
            } catch {
                throw error
            }
        }
        throw GeminiError.networkFailure
    }

    func makeRequest(
        imageJPEG: Data,
        apiKey: String,
        hemisphere: Hemisphere,
        date: Date
    ) throws -> URLRequest {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "scientific_name": ["type": "string"],
                "common_name": ["type": "string"],
                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                "watering_trigger": ["type": "string"],
                "watering_interval_spring": ["type": "integer", "minimum": 1, "maximum": 60],
                "watering_interval_summer": ["type": "integer", "minimum": 1, "maximum": 60],
                "watering_interval_autumn": ["type": "integer", "minimum": 1, "maximum": 60],
                "watering_interval_winter": ["type": "integer", "minimum": 1, "maximum": 60],
                "fertilizing_interval_days_growing_season": ["type": "integer", "minimum": 0, "maximum": 120],
                "fertilizing_notes": ["type": "string"],
                "light_requirement": [
                    "type": "string",
                    "enum": ["low", "medium", "bright_indirect", "direct_sun"]
                ],
                "toxicity_note": ["type": "string"],
                "care_note": ["type": "string"]
            ],
            "required": [
                "scientific_name", "common_name", "confidence", "watering_trigger",
                "watering_interval_spring", "watering_interval_summer",
                "watering_interval_autumn", "watering_interval_winter",
                "fertilizing_interval_days_growing_season", "fertilizing_notes",
                "light_requirement", "toxicity_note", "care_note"
            ],
            "additionalProperties": false
        ]

        let calendar = Calendar.current
        let month = calendar.monthSymbols[calendar.component(.month, from: date) - 1]
        let prompt = Self.prompt(hemisphere: hemisphere, month: month)
        let payload: [String: Any] = [
            "model": OpenRouterModel.plantIdentification,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": ["url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"]
                    ]
                ]
            ]],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "plant_identification",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "reasoning": ["effort": "low", "exclude": true],
            "provider": ["require_parameters": true],
            "stream": false
        ]

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/bn4t/plants", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Plants for iOS", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    func perform(_ request: URLRequest) async throws -> PlantIdentification {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GeminiError.networkFailure
        }

        guard let response = response as? HTTPURLResponse else {
            throw GeminiError.emptyResponse
        }
        if response.statusCode == 429 { throw GeminiError.rateLimited }
        guard (200..<300).contains(response.statusCode) else {
            throw GeminiError.badStatus(response.statusCode)
        }

        guard let responseBody = try? JSONDecoder().decode(OpenRouterResponse.self, from: data),
              let content = responseBody.choices.first?.message.content,
              !content.isEmpty
        else {
            throw GeminiError.emptyResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let result = try? decoder.decode(PlantIdentification.self, from: Data(content.utf8)) else {
            throw GeminiError.decodingFailure
        }
        let normalized = result.normalized
        let validLightValues = ["low", "medium", "bright_indirect", "direct_sun"]
        guard (!normalized.commonName.isEmpty || !normalized.scientificName.isEmpty),
              !normalized.wateringTrigger.isEmpty,
              validLightValues.contains(normalized.lightRequirement)
        else {
            throw GeminiError.invalidIdentification
        }
        return normalized
    }

    private struct OpenRouterResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }

            let message: Message
        }

        let choices: [Choice]
    }

    private static func prompt(hemisphere: Hemisphere, month: String) -> String {
        """
        Identify the houseplant in the photo and return concise, practical indoor care guidance.

        Context:
        - Hemisphere: \(hemisphere.displayName.lowercased())
        - Current month: \(month)

        The four watering numbers are starting intervals for checking the potting mix, not instructions to water automatically. Give species-appropriate seasonal baselines, but do not assume winter is always slower: indoor heating, light, temperature, humidity, pot size, and substrate may override the calendar. The app will learn from actual watering and damp-soil observations.

        Requirements:
        - Prefer species-level identification. Use low confidence if the image is unclear or not a plant.
        - watering_trigger must say what dryness to look or feel for before watering.
        - Fertilizer guidance applies only during active growth and must say to follow the product label.
        - Never advise fertilizing dry potting mix.
        - Keep toxicity and general care notes to one sentence each.
        - Return only JSON matching the schema.
        """
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
