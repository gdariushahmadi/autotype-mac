import Testing
import Foundation
@testable import AutoTypeCore

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("Handler not set.")
        }
        do {
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

@Suite("Translation", .serialized)
struct TranslationTests {

    @Test("Persian detection recognizes Persian text")
    func persianDetection() {
        #expect(PersianText.containsPersian("سلام دنیا"))
        #expect(PersianText.containsPersian("پروژه جدید"))
        #expect(PersianText.containsPersian("test سلام"))
        #expect(!PersianText.containsPersian("Hello world"))
        #expect(!PersianText.containsPersian("12345"))
        #expect(!PersianText.containsPersian("git commit -m \"fix\""))
    }

    @Test("Translation settings survive a JSON round trip")
    func settingsRoundTrip() throws {
        var settings = TranslationSettings()
        settings.isEnabled = true
        settings.provider = .gemini
        settings.endpoint = "https://example.com/v1/chat/completions"
        settings.apiKey = "secret-key-123"
        settings.model = "gemini-1.5-pro"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TranslationSettings.self, from: data)

        #expect(decoded == settings)
        #expect(decoded.isEnabled == true)
        #expect(decoded.provider == .gemini)
        #expect(decoded.apiKey == "secret-key-123")
    }

    @Test("Translation service parses MiniMax and OpenAI compatible responses")
    func miniMaxParsing() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.requestHandler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
            let responseJson = """
            {
                "choices": [
                    {
                        "message": {
                            "role": "assistant",
                            "content": "Hello, how are you?"
                        }
                    }
                ],
                "base_resp": {
                    "status_code": 0,
                    "status_msg": "success"
                }
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJson.utf8))
        }

        let service = TranslationService(session: session)
        var settings = TranslationSettings()
        settings.apiKey = "test-key"
        settings.endpoint = "https://api.minimax.chat/v1/text/chatcompletion_v2"

        let result = try await service.translate(text: "سلام چطوری؟", settings: settings)
        #expect(result == "Hello, how are you?")
    }

    @Test("Translation service parses native Gemini responses")
    func geminiNativeParsing() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.query?.contains("key=gemini-key") == true)
            let responseJson = """
            {
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": "Good morning"
                                }
                            ]
                        }
                    }
                ]
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJson.utf8))
        }

        let service = TranslationService(session: session)
        var settings = TranslationSettings()
        settings.apiKey = "gemini-key"
        settings.endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"

        let result = try await service.translate(text: "صبح بخیر", settings: settings)
        #expect(result == "Good morning")
    }

    @Test("Translation service throws on empty API key")
    func emptyKeyThrows() async {
        let service = TranslationService()
        var settings = TranslationSettings()
        settings.apiKey = ""

        await #expect(throws: TranslationService.TranslationError.self) {
            try await service.translate(text: "سلام", settings: settings)
        }
    }

    @Test("AI actions match start, end, and either position")
    func triggerPositions() {
        var settings = TranslationSettings(isEnabled: true, requireTriggerPrefix: true)

        // Translation action (default is .either)
        let trStart = settings.extractActionAndBody(from: "ترجمه سلام دنیا")
        #expect(trStart != nil)
        #expect(trStart?.body == "سلام دنیا")
        #expect(trStart?.position == .start)
        #expect(trStart?.action.name.contains("ترجمه") == true)

        let trEnd = settings.extractActionAndBody(from: "سلام دنیا ترجمه")
        #expect(trEnd != nil)
        #expect(trEnd?.body == "سلام دنیا")
        #expect(trEnd?.position == .end)

        let trColonEnd = settings.extractActionAndBody(from: "سلام دنیا :ترجمه")
        #expect(trColonEnd != nil)
        #expect(trColonEnd?.body == "سلام دنیا")
        #expect(trColonEnd?.position == .end)

        // Proofreading action (default is .either)
        let fixStart = settings.extractActionAndBody(from: "اصلاح این جمله غلط دارد")
        #expect(fixStart != nil)
        #expect(fixStart?.body == "این جمله غلط دارد")
        #expect(fixStart?.action.name.contains("اصلاح") == true)
        #expect(fixStart?.position == .start)

        let fixEnd = settings.extractActionAndBody(from: "این جمله غلط دارد اصلاح")
        #expect(fixEnd != nil)
        #expect(fixEnd?.body == "این جمله غلط دارد")
        #expect(fixEnd?.position == .end)

        let fixAlternativeTrigger = settings.extractActionAndBody(from: "این جمله غلط دارد ویرایش")
        #expect(fixAlternativeTrigger != nil)
        #expect(fixAlternativeTrigger?.body == "این جمله غلط دارد")

        // Action restricted to start only
        let startOnlyAction = AIAction(
            name: "خلاصه",
            trigger: "فقط‌شروع",
            position: .start,
            systemPrompt: "Summarize this."
        )
        settings.actions.append(startOnlyAction)

        #expect(settings.extractActionAndBody(from: "فقط‌شروع این متن طولانی است")?.body == "این متن طولانی است")
        #expect(settings.extractActionAndBody(from: "این متن طولانی است فقط‌شروع") == nil)

        // Action restricted to end only
        let endOnlyAction = AIAction(
            name: "رسمی",
            trigger: "فقط‌پایان",
            position: .end,
            systemPrompt: "Make it formal."
        )
        settings.actions.append(endOnlyAction)

        #expect(settings.extractActionAndBody(from: "سلام قربان حال شما فقط‌پایان")?.body == "سلام قربان حال شما")
        #expect(settings.extractActionAndBody(from: "فقط‌پایان سلام قربان حال شما") == nil)
    }

    @Test("Custom actions survive JSON round trip")
    func customActionsSerialization() throws {
        var settings = TranslationSettings()
        settings.isEnabled = true
        settings.actions = [
            AIAction(name: "ترجمه", trigger: "ترجمه, /tr", position: .either, systemPrompt: "Prompt 1"),
            AIAction(name: "اصلاح", trigger: "اصلاح, /fix", position: .end, systemPrompt: "Prompt 2"),
            AIAction(name: "توضیح", trigger: "توضیح", position: .start, systemPrompt: "Prompt 3")
        ]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TranslationSettings.self, from: data)

        #expect(decoded.actions.count == 3)
        #expect(decoded.actions[0].name == "ترجمه")
        #expect(decoded.actions[0].position == .either)
        #expect(decoded.actions[1].name == "اصلاح")
        #expect(decoded.actions[1].position == .end)
        #expect(decoded.actions[2].name == "توضیح")
        #expect(decoded.actions[2].position == .start)
    }
}
