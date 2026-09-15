import Foundation
import XCTest
@testable import NarrationCore

final class ElevenLabsTests: XCTestCase {
    private let endpoint = URL(string: "https://api.example.test")!

    func testSynthesisBuildsDocumentedRequestWithLanguageModelVoiceAndSettings() async throws {
        let recorder = RequestRecorder()
        let transport = ClosureElevenLabsTransport { request, _ in
            await recorder.record(request)
            return (
                Data([0x49, 0x44, 0x33]),
                try XCTUnwrap(HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "audio/mpeg",
                        "request-id": "req-123",
                        "character-cost": "42"
                    ]
                ))
            )
        }
        let client = ElevenLabsClient(
            apiKey: "test-api-key",
            transport: transport,
            baseURL: endpoint
        )

        let request = SpeechRequest(
            text: "Привет, Takelet",
            voiceID: "voice-ru-1",
            modelID: "eleven_flash_v2_5",
            languageCode: "RU",
            voiceSettings: VoiceSettings(
                stability: 0.4,
                similarityBoost: 0.8,
                style: 0.1,
                useSpeakerBoost: true
            )
        )
        let audio = try await client.synthesize(request)
        let lastRequest = await recorder.last()
        let sent = try XCTUnwrap(lastRequest)
        let body = try XCTUnwrap(sent.httpBody).flatMapJSONDictionary()

        XCTAssertEqual(audio.data, Data([0x49, 0x44, 0x33]))
        XCTAssertEqual(audio.contentType, "audio/mpeg")
        XCTAssertEqual(audio.requestID, "req-123")
        XCTAssertEqual(audio.characterCost, 42)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "xi-api-key"), "test-api-key")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.url?.path, "/v1/text-to-speech/voice-ru-1")
        XCTAssertEqual(sent.url?.query, "output_format=mp3_44100_128")
        XCTAssertEqual(body["text"] as? String, "Привет, Takelet")
        XCTAssertEqual(body["model_id"] as? String, "eleven_flash_v2_5")
        XCTAssertEqual(body["language_code"] as? String, "ru")
        let settings = try XCTUnwrap(body["voice_settings"] as? [String: Any])
        XCTAssertEqual(settings["stability"] as? Double, 0.4)
        XCTAssertEqual(settings["similarity_boost"] as? Double, 0.8)
        XCTAssertEqual(settings["use_speaker_boost"] as? Bool, true)
    }

    func testEmptyLanguageMeansAutomaticDetectionAndIsOmitted() async throws {
        let recorder = RequestRecorder()
        let transport = ClosureElevenLabsTransport { request, _ in
            await recorder.record(request)
            return (Data([0x01]), HTTPURLResponse.ok(for: request))
        }
        let client = ElevenLabsClient(apiKey: "key", transport: transport, baseURL: endpoint)

        _ = try await client.synthesize(SpeechRequest(
            text: "Detect this language",
            voiceID: "voice",
            languageCode: "  "
        ))
        let lastRequest = await recorder.last()
        let sent = try XCTUnwrap(lastRequest)
        let body = try XCTUnwrap(sent.httpBody).flatMapJSONDictionary()
        XCTAssertNil(body["language_code"])
    }

    func testMultilingualV2RejectsUnsupportedExplicitLanguageParameter() {
        let request = SpeechRequest(
            text: "Привет",
            voiceID: "voice",
            modelID: ElevenLabsDefaults.modelID,
            languageCode: "ru"
        )
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(
                error as? ElevenLabsError,
                .unsupportedLanguage(languageCode: "ru", modelID: ElevenLabsDefaults.modelID)
            )
        }
    }

    func testVoicePaginationAndDecoding() async throws {
        let recorder = RequestRecorder()
        let transport = ClosureElevenLabsTransport { request, _ in
            await recorder.record(request)
            let token = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "next_page_token" })?.value
            if token == nil {
                return (
                    Data(#"{"voices":[{"voice_id":"voice-1","name":"Mila","category":"premade","labels":{"accent":"Russian"},"verified_languages":[{"language":"ru","model_id":"eleven_multilingual_v2","locale":"ru-RU"}]}],"has_more":true,"next_page_token":"page-2","total_count":2}"#.utf8),
                    HTTPURLResponse.json(for: request)
                )
            }
            return (
                Data(#"{"voices":[{"voice_id":"voice-2","name":"Alex","category":"generated","labels":{}}],"has_more":false,"next_page_token":null,"total_count":2}"#.utf8),
                HTTPURLResponse.json(for: request)
            )
        }
        let client = ElevenLabsClient(apiKey: "key", transport: transport, baseURL: endpoint)

        let first = try await client.listVoices(pageSize: 1)
        let second = try await client.listVoices(pageSize: 1, nextPageToken: first.nextPageToken)
        let requests = await recorder.all()

        XCTAssertEqual(first.voices.first?.voiceID, "voice-1")
        XCTAssertEqual(first.voices.first?.name, "Mila")
        XCTAssertEqual(first.voices.first?.verifiedLanguages.first?.locale, "ru-RU")
        XCTAssertTrue(first.hasMore)
        XCTAssertEqual(first.nextPageToken, "page-2")
        XCTAssertEqual(second.voices.map(\.voiceID), ["voice-2"])
        XCTAssertFalse(second.hasMore)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(requests[0].url), resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "page_size" })?.value, "1")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(requests[1].url), resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "next_page_token" })?.value, "page-2")
    }

    func testMalformedVoiceResponseAndAudioContentTypeAreRejected() async throws {
        let malformed = ClosureElevenLabsTransport { request, _ in
            (Data("not-json".utf8), HTTPURLResponse.json(for: request))
        }
        let client = ElevenLabsClient(apiKey: "key", transport: malformed, baseURL: endpoint)
        do {
            _ = try await client.listVoices()
            XCTFail("Expected malformed voice response")
        } catch let error as ElevenLabsError {
            guard case .malformedResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let textResponse = ClosureElevenLabsTransport { request, _ in
            (Data("provider body".utf8), HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/plain"]
            )!)
        }
        let audioClient = ElevenLabsClient(apiKey: "key", transport: textResponse, baseURL: endpoint)
        do {
            _ = try await audioClient.synthesize(SpeechRequest(text: "Hello", voiceID: "voice"))
            XCTFail("Expected invalid audio content type")
        } catch let error as ElevenLabsError {
            XCTAssertEqual(error, .invalidAudioContentType("text/plain"))
        }
    }

    func testHTTPErrorsAreUsefulAndNeverEchoTheAPIKey() async throws {
        let secret = "super-secret-api-key"
        let transport = ClosureElevenLabsTransport { request, _ in
            let body = #"{"detail":{"status":"invalid_api_key","message":"Invalid API key super-secret-api-key"}}"#
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        let client = ElevenLabsClient(apiKey: secret, transport: transport, baseURL: endpoint)

        do {
            _ = try await client.listVoices()
            XCTFail("Expected authentication error")
        } catch let error as ElevenLabsError {
            let message = error.localizedDescription
            XCTAssertTrue(message.localizedCaseInsensitiveContains("API key"))
            XCTAssertFalse(message.contains(secret))
            guard case let .http(statusCode, kind, detail) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(kind, .authentication)
            XCTAssertEqual(detail, "Invalid API key [redacted]")
        }
    }

    func testStructuredQuotaErrorWinsOverAuthenticationStatus() async throws {
        let transport = ClosureElevenLabsTransport { request, _ in
            let body = #"{"detail":{"status":"quota_exceeded","message":"Character quota exceeded"}}"#
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        let client = ElevenLabsClient(apiKey: "key", transport: transport, baseURL: endpoint)

        do {
            _ = try await client.listVoices()
            XCTFail("Expected quota error")
        } catch let error as ElevenLabsError {
            guard case let .http(statusCode, kind, message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(kind, .quota)
            XCTAssertEqual(message, "Character quota exceeded")
        }
    }

    func testCrossOriginResponseIsRejected() async throws {
        let transport = ClosureElevenLabsTransport { request, _ in
            (
                Data(#"{"voices":[],"has_more":false}"#.utf8),
                HTTPURLResponse(
                    url: URL(string: "https://attacker.example/collect")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }
        let client = ElevenLabsClient(apiKey: "key", transport: transport, baseURL: endpoint)

        do {
            _ = try await client.listVoices()
            XCTFail("Expected cross-origin redirect protection")
        } catch let error as ElevenLabsError {
            XCTAssertEqual(error, .redirectRefused)
        }
    }

    func testCancellationPropagatesWithoutConvertingToProviderError() async throws {
        let transport = ClosureElevenLabsTransport { _, _ in
            try await Task.sleep(for: .seconds(5))
            return (Data(), URLResponse())
        }
        let client = ElevenLabsClient(apiKey: "key", transport: transport, baseURL: endpoint)
        let task = Task {
            try await client.synthesize(SpeechRequest(text: "Hello", voiceID: "voice"))
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected. Cancellation remains distinguishable from network and
            // provider failures for the UI.
        }
    }

    func testTotalRequestTimeoutIsBounded() async throws {
        let transport = ClosureElevenLabsTransport { _, _ in
            try await Task.sleep(for: .seconds(5))
            return (Data([0x01]), URLResponse())
        }
        let client = ElevenLabsClient(
            apiKey: "key",
            transport: transport,
            baseURL: endpoint,
            requestTimeout: 1
        )

        do {
            _ = try await client.synthesize(SpeechRequest(text: "Hello", voiceID: "voice"))
            XCTFail("Expected total request timeout")
        } catch let error as ElevenLabsError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func testRequestAndResponseLimitsAreEnforced() async throws {
        let oversizedText = String(repeating: "x", count: 10_001)
        XCTAssertThrowsError(try SpeechRequest(text: oversizedText, voiceID: "voice").validate()) { error in
            XCTAssertEqual(error as? ElevenLabsError, .textTooLong(actual: 10_001, maximum: 10_000))
        }

        let transport = ClosureElevenLabsTransport { request, _ in
            (Data(repeating: 0, count: 1_024), HTTPURLResponse.audio(for: request))
        }
        let client = ElevenLabsClient(
            apiKey: "key",
            transport: transport,
            baseURL: endpoint,
            maximumResponseBytes: 128
        )
        do {
            _ = try await client.synthesize(SpeechRequest(text: "Hello", voiceID: "voice"))
            XCTFail("Expected bounded response error")
        } catch let error as ElevenLabsError {
            XCTAssertEqual(error, .responseTooLarge(maximumBytes: 128))
        }
    }
}

private actor RequestRecorder {
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func last() -> URLRequest? {
        requests.last
    }

    func all() -> [URLRequest] {
        requests
    }
}

private extension Data {
    func flatMapJSONDictionary() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
    }
}

private extension HTTPURLResponse {
    static func ok(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "audio/mpeg"]
        )!
    }

    static func json(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    static func audio(for request: URLRequest) -> HTTPURLResponse {
        ok(for: request)
    }
}
