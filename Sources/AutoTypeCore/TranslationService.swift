import Foundation

/// Service for translating text via AI (MiniMax, Google Gemini, OpenAI, etc.).
public final class TranslationService: @unchecked Sendable {

    public static let shared = TranslationService()

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config)
        }
    }

    public enum TranslationError: LocalizedError {
        case emptyAPIKey
        case invalidEndpoint
        case invalidResponse
        case httpError(statusCode: Int, message: String)
        case apiError(message: String)
        case emptyTranslation

        public var errorDescription: String? {
            switch self {
            case .emptyAPIKey:
                return "API key is missing. Please configure your key in AutoType Settings."
            case .invalidEndpoint:
                return "Invalid API endpoint URL."
            case .invalidResponse:
                return "Invalid or unparseable response from translation server."
            case .httpError(let statusCode, let message):
                return "Server returned HTTP \(statusCode): \(message)"
            case .apiError(let message):
                return "API error: \(message)"
            case .emptyTranslation:
                return "The translation service returned empty text."
            }
        }
    }

    /// Translates text using the provided settings.
    public func translate(text: String, settings: TranslationSettings) async throws -> String {
        return try await process(text: text, systemPrompt: settings.systemPrompt, settings: settings)
    }

    /// Processes text with the AI model using an optional custom system prompt (or the settings default prompt).
    public func process(text: String, systemPrompt: String? = nil, settings: TranslationSettings) async throws -> String {
        let trimmedKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw TranslationError.emptyAPIKey
        }

        var endpointStr = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpointStr.isEmpty {
            endpointStr = settings.provider.defaultEndpoint
        }

        guard var components = URLComponents(string: endpointStr),
              let host = components.host, !host.isEmpty else {
            throw TranslationError.invalidEndpoint
        }

        let isGeminiNative = endpointStr.contains("generateContent")

        if isGeminiNative {
            // Append key as query parameter if not present
            var queryItems = components.queryItems ?? []
            if !queryItems.contains(where: { $0.name == "key" }) {
                queryItems.append(URLQueryItem(name: "key", value: trimmedKey))
                components.queryItems = queryItems
            }
        }

        guard let url = components.url else {
            throw TranslationError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !isGeminiNative {
            request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }

        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? settings.provider.defaultModel
            : settings.model.trimmingCharacters(in: .whitespacesAndNewlines)

        let effectivePrompt = (systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? systemPrompt!
            : settings.systemPrompt

        let payloadData: Data
        if isGeminiNative {
            let nativePayload: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": effectivePrompt]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.2
                ]
            ]
            payloadData = try JSONSerialization.data(withJSONObject: nativePayload)
        } else {
            let standardPayload: [String: Any] = [
                "model": model,
                "messages": [
                    [
                        "role": "system",
                        "content": effectivePrompt
                    ],
                    [
                        "role": "user",
                        "content": text
                    ]
                ],
                "temperature": 0.2
            ]
            payloadData = try JSONSerialization.data(withJSONObject: standardPayload)
        }

        request.httpBody = payloadData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranslationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw TranslationError.httpError(statusCode: httpResponse.statusCode, message: errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationError.invalidResponse
        }

        // MiniMax base_resp check
        if let baseResp = json["base_resp"] as? [String: Any],
           let statusCode = baseResp["status_code"] as? Int, statusCode != 0 {
            let statusMsg = baseResp["status_msg"] as? String ?? "MiniMax error \(statusCode)"
            throw TranslationError.apiError(message: statusMsg)
        }

        // Native Gemini response
        if isGeminiNative {
            if let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let resultText = firstPart["text"] as? String {
                let cleaned = Self.cleanResponse(resultText)
                if cleaned.isEmpty { throw TranslationError.emptyTranslation }
                return cleaned
            }
        }

        // OpenAI / MiniMax choices response
        if let choices = json["choices"] as? [[String: Any]], let firstChoice = choices.first {
            if let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                let cleaned = Self.cleanResponse(content)
                if cleaned.isEmpty { throw TranslationError.emptyTranslation }
                return cleaned
            } else if let textResult = firstChoice["text"] as? String {
                let cleaned = Self.cleanResponse(textResult)
                if cleaned.isEmpty { throw TranslationError.emptyTranslation }
                return cleaned
            }
        }

        throw TranslationError.invalidResponse
    }

    /// Removes reasoning `<think>...</think>` blocks and surrounding whitespace.
    private static func cleanResponse(_ raw: String) -> String {
        let withoutThink = raw.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>",
            with: "",
            options: .regularExpression
        )
        return withoutThink.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tests connection and translation with sample text.
    public func testConnection(settings: TranslationSettings, systemPrompt: String? = nil) async throws -> String {
        return try await process(text: "سلام دنیا", systemPrompt: systemPrompt, settings: settings)
    }
}
