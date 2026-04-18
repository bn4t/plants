import Foundation

struct PlantIdentification: Codable {
    let scientificName: String
    let commonName: String
    let confidence: String
    let wateringIntervalDaysMin: Int
    let wateringIntervalDaysMax: Int
    let wateringTrigger: String
    let fertilizingIntervalDaysGrowingSeason: Int
    let fertilizingNotes: String
    let lightRequirement: String
    let toxicityNote: String
    let careNote: String

    var suggestedWateringInterval: Int {
        (wateringIntervalDaysMin + wateringIntervalDaysMax) / 2
    }

    static let manualFallback = PlantIdentification(
        scientificName: "",
        commonName: "",
        confidence: "low",
        wateringIntervalDaysMin: 7,
        wateringIntervalDaysMax: 7,
        wateringTrigger: "",
        fertilizingIntervalDaysGrowingSeason: 0,
        fertilizingNotes: "",
        lightRequirement: "medium",
        toxicityNote: "",
        careNote: ""
    )
}

enum GeminiError: Error, LocalizedError {
    case missingAPIKey
    case networkFailure(Error)
    case badStatus(Int)
    case emptyResponse
    case decodingFailure(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your OpenRouter API key in Settings before identifying a plant."
        case .networkFailure:
            return "Could not reach the plant identification service. Check your connection and try again."
        case .badStatus(let code):
            return "Plant identification failed (HTTP \(code)). Try again or enter the plant details manually."
        case .emptyResponse:
            return "The plant identification service returned no result. Try another photo."
        case .decodingFailure:
            return "Could not read the plant identification response. Try again."
        }
    }
}

actor GeminiClient {
    static let shared = GeminiClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    func identify(imageJPEG: Data) async throws -> PlantIdentification {
        let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        let base64Image = imageJPEG.base64EncodedString()
        let imageURL = "data:image/jpeg;base64,\(base64Image)"

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "scientific_name": ["type": "string"],
                "common_name": ["type": "string"],
                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                "watering_interval_days_min": ["type": "integer", "minimum": 1, "maximum": 60],
                "watering_interval_days_max": ["type": "integer", "minimum": 1, "maximum": 60],
                "watering_trigger": ["type": "string"],
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
                "scientific_name",
                "common_name",
                "confidence",
                "watering_interval_days_min",
                "watering_interval_days_max",
                "watering_trigger",
                "fertilizing_interval_days_growing_season",
                "light_requirement"
            ],
            "additionalProperties": false
        ]

        let payload: [String: Any] = [
            "model": "google/gemini-3-flash-preview",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": Self.prompt
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": imageURL
                            ]
                        ]
                    ]
                ]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "plant_identification",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "stream": false
        ]

        guard let apiKey = Secrets.openRouterAPIKey else {
            throw GeminiError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GeminiError.emptyResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                throw GeminiError.badStatus(httpResponse.statusCode)
            }

            let decodedResponse: OpenRouterResponse
            do {
                decodedResponse = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            } catch {
                throw GeminiError.decodingFailure(error)
            }

            guard let content = decodedResponse.choices.first?.message.content,
                  !content.isEmpty
            else {
                throw GeminiError.emptyResponse
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                return try decoder.decode(PlantIdentification.self, from: Data(content.utf8))
            } catch {
                throw GeminiError.decodingFailure(error)
            }
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.networkFailure(error)
        }
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

    private static let prompt = """
    You are a botanical expert assistant. Identify the plant in this photo and provide practical care guidelines for an indoor houseplant setting in Switzerland (temperate, moderate humidity).

    Rules:
    - Prefer species-level identification. If the cultivar is unclear, give the species.
    - If the image does not clearly contain a plant, set confidence to "low" and make your best guess.
    - watering_interval_days_min and watering_interval_days_max should bracket a realistic range for a healthy plant kept indoors in typical room conditions.
    - watering_trigger should be a short, human-readable rule of thumb, such as "when the top 2cm of soil is dry".
    - fertilizing_interval_days_growing_season: days between fertilizing during the active growing season (spring / summer). Use 0 if the plant does not typically need fertilizing.
    - fertilizing_notes should mention any seasonal considerations, such as "skip in winter" or "use half-strength liquid fertilizer".
    - light_requirement: one of low, medium, bright_indirect, direct_sun.
    - toxicity_note: one sentence on toxicity to pets or humans, or empty if not toxic.
    - care_note: one short overall tip.

    Return ONLY JSON matching the provided schema. Do not include markdown code fences or commentary.
    """
}
