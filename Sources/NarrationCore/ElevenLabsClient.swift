import Foundation

public enum ElevenLabsDefaults {
    /// ElevenLabs describes Multilingual v2 as its most stable model for
    /// long-form generations.
    public static let modelID = "eleven_multilingual_v2"
    /// MP3 44.1 kHz at 128 kbps is broadly available and suitable for the
    /// narration track used by Takelet.
    public static let outputFormat = "mp3_44100_128"
}

public struct VoiceLanguage: Codable, Equatable, Hashable, Sendable {
    public let language: String
    public let modelID: String
    public let accent: String?
    public let locale: String?
    public let previewURL: URL?

    public init(
        language: String,
        modelID: String,
        accent: String? = nil,
        locale: String? = nil,
        previewURL: URL? = nil
    ) {
        self.language = language
        self.modelID = modelID
        self.accent = accent
        self.locale = locale
        self.previewURL = previewURL
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case modelID = "model_id"
        case accent
        case locale
        case previewURL = "preview_url"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decode(String.self, forKey: .language)
        modelID = try values.decode(String.self, forKey: .modelID)
        accent = try values.decodeIfPresent(String.self, forKey: .accent)
        locale = try values.decodeIfPresent(String.self, forKey: .locale)
        previewURL = try values.decodeIfPresent(URL.self, forKey: .previewURL)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(language, forKey: .language)
        try values.encode(modelID, forKey: .modelID)
        try values.encodeIfPresent(accent, forKey: .accent)
        try values.encodeIfPresent(locale, forKey: .locale)
        try values.encodeIfPresent(previewURL, forKey: .previewURL)
    }
}

/// A voice returned by ElevenLabs' `/v2/voices` endpoint.
public struct Voice: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let voiceID: String
    public var id: String { voiceID }
    public let name: String
    public let category: String?
    public let labels: [String: String]
    public let description: String?
    public let previewURL: URL?
    public let verifiedLanguages: [VoiceLanguage]

    public init(
        id: String,
        name: String,
        category: String? = nil,
        labels: [String: String] = [:],
        description: String? = nil,
        previewURL: URL? = nil,
        verifiedLanguages: [VoiceLanguage] = []
    ) {
        self.voiceID = id
        self.name = name
        self.category = category
        self.labels = labels
        self.description = description
        self.previewURL = previewURL
        self.verifiedLanguages = verifiedLanguages
    }

    public init(
        voiceID: String,
        name: String,
        category: String? = nil,
        labels: [String: String] = [:],
        description: String? = nil,
        previewURL: URL? = nil,
        verifiedLanguages: [VoiceLanguage] = []
    ) {
        self.init(
            id: voiceID,
            name: name,
            category: category,
            labels: labels,
            description: description,
            previewURL: previewURL,
            verifiedLanguages: verifiedLanguages
        )
    }

    private enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id"
        case name
        case category
        case labels
        case description
        case previewURL = "preview_url"
        case verifiedLanguages = "verified_languages"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        voiceID = try values.decode(String.self, forKey: .voiceID)
        name = try values.decode(String.self, forKey: .name)
        category = try values.decodeIfPresent(String.self, forKey: .category)
        labels = try values.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        description = try values.decodeIfPresent(String.self, forKey: .description)
        previewURL = try values.decodeIfPresent(URL.self, forKey: .previewURL)
        verifiedLanguages = try values.decodeIfPresent([VoiceLanguage].self, forKey: .verifiedLanguages) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(voiceID, forKey: .voiceID)
        try values.encode(name, forKey: .name)
        try values.encodeIfPresent(category, forKey: .category)
        try values.encode(labels, forKey: .labels)
        try values.encodeIfPresent(description, forKey: .description)
        try values.encodeIfPresent(previewURL, forKey: .previewURL)
        try values.encode(verifiedLanguages, forKey: .verifiedLanguages)
    }
}

public struct VoicePage: Codable, Equatable, Sendable {
    public let voices: [Voice]
    public let hasMore: Bool
    public let nextPageToken: String?
    public let totalCount: Int?

    public init(
        voices: [Voice],
        hasMore: Bool,
        nextPageToken: String? = nil,
        totalCount: Int? = nil
    ) {
        self.voices = voices
        self.hasMore = hasMore
        self.nextPageToken = nextPageToken
        self.totalCount = totalCount
    }

    private enum CodingKeys: String, CodingKey {
        case voices
        case hasMore = "has_more"
        case nextPageToken = "next_page_token"
        case totalCount = "total_count"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        voices = try values.decode([Voice].self, forKey: .voices)
        hasMore = try values.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        nextPageToken = try values.decodeIfPresent(String.self, forKey: .nextPageToken)
        totalCount = try values.decodeIfPresent(Int.self, forKey: .totalCount)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(voices, forKey: .voices)
        try values.encode(hasMore, forKey: .hasMore)
        try values.encodeIfPresent(nextPageToken, forKey: .nextPageToken)
        try values.encodeIfPresent(totalCount, forKey: .totalCount)
    }
}

public struct VoiceSettings: Codable, Equatable, Sendable {
    public var stability: Double?
    public var similarityBoost: Double?
    public var style: Double?
    public var useSpeakerBoost: Bool?
    public var speed: Double?

    public init(
        stability: Double? = nil,
        similarityBoost: Double? = nil,
        style: Double? = nil,
        useSpeakerBoost: Bool? = nil,
        speed: Double? = nil
    ) {
        self.stability = stability
        self.similarityBoost = similarityBoost
        self.style = style
        self.useSpeakerBoost = useSpeakerBoost
        self.speed = speed
    }

    private enum CodingKeys: String, CodingKey {
        case stability
        case similarityBoost = "similarity_boost"
        case style
        case useSpeakerBoost = "use_speaker_boost"
        case speed
    }
}

public struct SpeechRequest: Equatable, Sendable {
    public let text: String
    public let voiceID: String
    public let modelID: String
    /// A two-letter ISO 639-1 code. `nil` means that ElevenLabs should detect
    /// the language from the text (the UI can pass an empty field for auto).
    public let languageCode: String?
    public let voiceSettings: VoiceSettings?
    public let outputFormat: String

    public init(
        text: String,
        voiceID: String,
        modelID: String = ElevenLabsDefaults.modelID,
        languageCode: String? = nil,
        voiceSettings: VoiceSettings? = nil,
        outputFormat: String = ElevenLabsDefaults.outputFormat
    ) {
        self.text = text
        self.voiceID = voiceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLanguage = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.languageCode = normalizedLanguage?.isEmpty == true ? nil : normalizedLanguage?.lowercased()
        self.voiceSettings = voiceSettings
        self.outputFormat = outputFormat.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var characterCount: Int { text.count }

    public func validate(maxTextLength override: Int? = nil) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ElevenLabsError.invalidRequest("Narration text cannot be empty.")
        }
        guard Self.isSafeIdentifier(voiceID, maximum: 256) else {
            throw ElevenLabsError.invalidRequest("Choose a valid ElevenLabs voice ID.")
        }
        guard Self.isSafeIdentifier(modelID, maximum: 100) else {
            throw ElevenLabsError.invalidRequest("Choose a valid ElevenLabs model ID.")
        }
        let maximum = override ?? Self.maximumTextLength(for: modelID)
        guard characterCount <= maximum else {
            throw ElevenLabsError.textTooLong(actual: characterCount, maximum: maximum)
        }
        if let languageCode {
            guard Self.isISO6391(languageCode) else {
                throw ElevenLabsError.invalidRequest("Language must be a two-letter ISO 639-1 code such as en or ru, or empty for auto.")
            }
            if !Self.supportsExplicitLanguageCode(for: modelID) {
                throw ElevenLabsError.unsupportedLanguage(languageCode: languageCode, modelID: modelID)
            }
        }
        guard Self.isValidOutputFormat(outputFormat) else {
            throw ElevenLabsError.invalidRequest("Choose a documented ElevenLabs audio output format.")
        }
        if let voiceSettings {
            try validate(voiceSettings)
        }
    }

    public static func maximumTextLength(for modelID: String) -> Int {
        switch modelID.lowercased() {
        case "eleven_v3": return 5_000
        case "eleven_flash_v2_5", "eleven_turbo_v2_5": return 40_000
        case "eleven_flash_v2", "eleven_turbo_v2": return 30_000
        case "eleven_multilingual_v1", "eleven_multilingual_v2", "eleven_english_v1", "eleven_english_v2": return 10_000
        default: return 10_000
        }
    }

    // The API reference currently documents language_code as unsupported for
    // Multilingual v2. Its language is detected from the supplied text;
    // models that expose explicit language selection remain accepted here.
    public static func supportsExplicitLanguageCode(for modelID: String) -> Bool {
        modelID.lowercased() != "eleven_multilingual_v2"
    }

    private func validate(_ settings: VoiceSettings) throws {
        for (value, name) in [(settings.stability, "stability"), (settings.similarityBoost, "similarity boost"), (settings.style, "style")] {
            if let value, (!value.isFinite || !(0...1).contains(value)) {
                throw ElevenLabsError.invalidRequest("Voice \(name) must be between 0 and 1.")
            }
        }
        if let speed = settings.speed, (!speed.isFinite || !(0.7...1.2).contains(speed)) {
            throw ElevenLabsError.invalidRequest("Voice speed must be between 0.7 and 1.2.")
        }
    }

    private static func isSafeIdentifier(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.count <= maximum && value.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) && !"/\\?#".unicodeScalars.contains($0)
        }
    }

    private static func isISO6391(_ value: String) -> Bool {
        value.count == 2 && value.unicodeScalars.allSatisfy {
            ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122)
        }
    }

    private static func isValidOutputFormat(_ value: String) -> Bool {
        guard value.count <= 64, !value.isEmpty else { return false }
        let parts = value.split(separator: "_", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              ["mp3", "pcm", "ulaw", "alaw", "opus"].contains(String(parts[0])) else { return false }
        return parts.dropFirst().allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isNumber }
        }
    }
}

public struct SynthesizedAudio: Equatable, Sendable {
    public let data: Data
    public let contentType: String
    public let requestID: String?
    public let traceID: String?
    public let characterCost: Int?

    public init(
        data: Data,
        contentType: String,
        requestID: String? = nil,
        traceID: String? = nil,
        characterCost: Int? = nil
    ) {
        self.data = data
        self.contentType = contentType
        self.requestID = requestID
        self.traceID = traceID
        self.characterCost = characterCost
    }
}

public protocol NarrationService: Sendable {
    func listVoices(pageSize: Int, nextPageToken: String?) async throws -> VoicePage
    func synthesize(_ request: SpeechRequest) async throws -> SynthesizedAudio
}

public extension NarrationService {
    func listVoices() async throws -> VoicePage {
        try await listVoices(pageSize: 100, nextPageToken: nil)
    }

    func listVoices(pageSize: Int) async throws -> VoicePage {
        try await listVoices(pageSize: pageSize, nextPageToken: nil)
    }

    func synthesize(
        text: String,
        voiceID: String,
        modelID: String = ElevenLabsDefaults.modelID,
        languageCode: String? = nil,
        voiceSettings: VoiceSettings? = nil,
        outputFormat: String = ElevenLabsDefaults.outputFormat
    ) async throws -> SynthesizedAudio {
        try await synthesize(SpeechRequest(
            text: text,
            voiceID: voiceID,
            modelID: modelID,
            languageCode: languageCode,
            voiceSettings: voiceSettings,
            outputFormat: outputFormat
        ))
    }
}

public enum ElevenLabsTransportError: Error, LocalizedError, Sendable, Equatable {
    case responseTooLarge(maximumBytes: Int)
    case timedOut
    case redirectRefused

    public var errorDescription: String? {
        switch self {
        case let .responseTooLarge(maximumBytes):
            return "The ElevenLabs response exceeded the " + String(maximumBytes) + "-byte safety limit."
        case .timedOut:
            return "The ElevenLabs request exceeded its time limit."
        case .redirectRefused:
            return "The ElevenLabs request was redirected to a different origin."
        }
    }
}

/// The transport boundary keeps HTTP out of unit tests and lets production
/// use a streaming URLSession implementation with a hard response limit.
public protocol ElevenLabsTransport: Sendable {
    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse)
}

/// A convenient transport adapter for unit tests or an application-specific
/// networking layer.
public struct ClosureElevenLabsTransport: ElevenLabsTransport, Sendable {
    public typealias Handler = @Sendable (URLRequest, Int) async throws -> (Data, URLResponse)
    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        try await handler(request, maximumBytes)
    }
}

/// A URLSession transport that bounds response memory and refuses redirects
/// away from the configured origin. `URLSession.data(for:)` would otherwise
/// buffer an unbounded response before the client can inspect its size.
public struct URLSessionElevenLabsTransport: ElevenLabsTransport, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let allowedOrigin: URL
    private let timeoutInterval: TimeInterval

    public init(
        session: URLSession = .shared,
        allowedOrigin: URL,
        timeoutInterval: TimeInterval = 120
    ) {
        let configuration = (session.configuration.copy() as? URLSessionConfiguration) ?? session.configuration
        if timeoutInterval.isFinite, timeoutInterval > 0 {
            configuration.timeoutIntervalForResource = timeoutInterval
        }
        self.configuration = configuration
        self.allowedOrigin = allowedOrigin
        self.timeoutInterval = timeoutInterval
    }

    public func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, URLResponse) {
        guard maximumBytes > 0 else {
            throw ElevenLabsTransportError.responseTooLarge(maximumBytes: maximumBytes)
        }
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            throw ElevenLabsTransportError.timedOut
        }
        try Task.checkCancellation()

        // Use a session owned by this request. If a response is rejected for
        // exceeding the limit, invalidating this session cancels the actual
        // URLSessionTask instead of leaving a streaming task attached to a
        // shared session.
        let session = URLSession(configuration: configuration)
        let delegate = RedirectGuardDelegate(allowedOrigin: allowedOrigin)
        var completed = false
        defer {
            if completed {
                session.finishTasksAndInvalidate()
            } else {
                session.invalidateAndCancel()
            }
        }

        return try await withTaskCancellationHandler {
          do {
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            let contentLength = response.expectedContentLength
            if contentLength >= 0, contentLength > Int64(maximumBytes) {
                throw ElevenLabsTransportError.responseTooLarge(maximumBytes: maximumBytes)
            }
            var data = Data()
            if contentLength > 0, contentLength <= Int64(maximumBytes) {
                data.reserveCapacity(Int(contentLength))
            }
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else {
                    throw ElevenLabsTransportError.responseTooLarge(maximumBytes: maximumBytes)
                }
                data.append(byte)
            }
            completed = true
            return (data, response)
          } catch {
            if delegate.redirectWasRefused {
                throw ElevenLabsTransportError.redirectRefused
            }
            throw error
          }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }
}

private final class RedirectGuardDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowedOrigin: URL
    private let lock = NSLock()
    private var didRefuseRedirect = false

    init(allowedOrigin: URL) {
        self.allowedOrigin = allowedOrigin
    }

    var redirectWasRefused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didRefuseRedirect
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let newURL = request.url, Self.sameOrigin(newURL, allowedOrigin) else {
            // Returning nil aborts the redirect before URLSession sends the
            // request, so the xi-api-key header cannot cross an origin.
            lock.lock()
            didRefuseRedirect = true
            lock.unlock()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsScheme = lhs.scheme?.lowercased(),
              let rhsScheme = rhs.scheme?.lowercased(),
              let lhsHost = lhs.host?.lowercased(),
              let rhsHost = rhs.host?.lowercased() else { return false }
        return lhsScheme == rhsScheme && lhsHost == rhsHost && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "http" ? 80 : 443
    }
}

public enum ElevenLabsHTTPErrorKind: String, Equatable, Sendable {
    case authentication
    case quota
    case rateLimit
    case voice
    case language
    case model
    case validation
    case notFound
    case server
    case unknown
}

public enum ElevenLabsError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidRequest(String)
    case textTooLong(actual: Int, maximum: Int)
    case unsupportedLanguage(languageCode: String, modelID: String)
    case invalidEndpoint
    case invalidResponse
    case malformedResponse(String)
    case invalidAudioContentType(String?)
    case responseTooLarge(maximumBytes: Int)
    case timeout
    case redirectRefused
    case network(code: Int)
    case http(statusCode: Int, kind: ElevenLabsHTTPErrorKind, message: String?)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add an ElevenLabs API key in Takelet settings before generating narration."
        case let .invalidRequest(message):
            return message
        case let .textTooLong(actual, maximum):
            return "Narration text is " + String(actual) + " characters; this model allows at most " + String(maximum) + " characters per request."
        case let .unsupportedLanguage(languageCode, modelID):
            return "The ElevenLabs model " + modelID + " does not support an explicit " + languageCode + " language selection. Leave language empty for automatic detection or choose a model that supports language_code."
        case .invalidEndpoint:
            return "The ElevenLabs endpoint is invalid."
        case .invalidResponse:
            return "ElevenLabs returned an invalid HTTP response."
        case let .malformedResponse(message):
            return "ElevenLabs returned an unexpected response: " + message
        case let .invalidAudioContentType(contentType):
            let suffix = contentType.map { " (" + $0 + ")" } ?? ""
            return "ElevenLabs returned an unsupported audio content type" + suffix + "."
        case let .responseTooLarge(maximumBytes):
            return "The ElevenLabs response exceeded the " + String(maximumBytes) + "-byte safety limit."
        case .timeout:
            return "The ElevenLabs request timed out. Try again when the connection is stable."
        case .redirectRefused:
            return "The ElevenLabs request was redirected to a different origin and was blocked for security."
        case let .network(code):
            return "The ElevenLabs request could not be completed (network error " + String(code) + ")."
        case let .http(statusCode, kind, message):
            let base: String
            switch kind {
            case .authentication: base = "ElevenLabs rejected the API key."
            case .quota: base = "The ElevenLabs account has insufficient quota."
            case .rateLimit: base = "ElevenLabs rate-limited this request. Try again later."
            case .voice: base = "The selected ElevenLabs voice was not found or is unavailable."
            case .language: base = "The selected language is not supported by this ElevenLabs model."
            case .model: base = "The selected ElevenLabs model is unavailable or does not support text to speech."
            case .validation: base = "ElevenLabs rejected the narration request."
            case .notFound: base = "The requested ElevenLabs resource was not found."
            case .server: base = "ElevenLabs reported a server error."
            case .unknown: base = "ElevenLabs returned HTTP status " + String(statusCode) + "."
            }
            if let message, !message.isEmpty { return base + " " + message }
            return base
        }
    }
}

public final class ElevenLabsClient: NarrationService, @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://api.elevenlabs.io")!
    public static let defaultModelID = ElevenLabsDefaults.modelID
    public static let defaultOutputFormat = ElevenLabsDefaults.outputFormat
    public static let defaultMaximumResponseBytes = 32 * 1024 * 1024

    private let apiKey: String
    private let baseURL: URL
    private let transport: any ElevenLabsTransport
    private let requestTimeout: TimeInterval
    private let maximumResponseBytes: Int

    /// `transport` is injectable for tests. With no transport, the client uses
    /// a streaming URLSession transport that enforces same-origin redirects.
    public init(
        apiKey: String,
        transport: (any ElevenLabsTransport)? = nil,
        session: URLSession = .shared,
        baseURL: URL = ElevenLabsClient.defaultBaseURL,
        requestTimeout: TimeInterval = 120,
        maximumResponseBytes: Int = ElevenLabsClient.defaultMaximumResponseBytes
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        self.maximumResponseBytes = maximumResponseBytes
        self.transport = transport ?? URLSessionElevenLabsTransport(
            session: session,
            allowedOrigin: baseURL,
            timeoutInterval: requestTimeout
        )
    }

    public func listVoices(pageSize: Int = 100, nextPageToken: String? = nil) async throws -> VoicePage {
        try Task.checkCancellation()
        guard hasUsableAPIKey else { throw ElevenLabsError.missingAPIKey }
        guard (1...100).contains(pageSize) else {
            throw ElevenLabsError.invalidRequest("Voice page size must be between 1 and 100.")
        }
        let token = try normalizedPageToken(nextPageToken)
        let url = try makeURL(path: "/v2/voices", queryItems: [
            URLQueryItem(name: "page_size", value: String(pageSize)),
            token.map { URLQueryItem(name: "next_page_token", value: $0) }
        ].compactMap { $0 })
        var request = try makeRequest(url: url, method: "GET", accept: "application/json")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await perform(request, context: .voices)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard let contentType = normalizedContentType(httpResponse), isJSONContentType(contentType) else {
            throw ElevenLabsError.malformedResponse("Expected a JSON voice-list response.")
        }
        do {
            let page = try JSONDecoder().decode(VoicePage.self, from: data)
            guard page.voices.count <= 1_000 else {
                throw ElevenLabsError.malformedResponse("The voice page contained too many voices.")
            }
            if page.hasMore && (page.nextPageToken?.isEmpty != false) {
                throw ElevenLabsError.malformedResponse("The voice page did not include its next-page token.")
            }
            return page
        } catch let error as ElevenLabsError {
            throw error
        } catch {
            throw ElevenLabsError.malformedResponse("The voice list could not be decoded.")
        }
    }

    public func synthesize(_ request: SpeechRequest) async throws -> SynthesizedAudio {
        try Task.checkCancellation()
        guard hasUsableAPIKey else { throw ElevenLabsError.missingAPIKey }
        try request.validate()

        let encodedVoiceID = request.voiceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let encodedVoiceID, !encodedVoiceID.isEmpty else {
            throw ElevenLabsError.invalidRequest("Choose a valid ElevenLabs voice ID.")
        }
        let url = try makeURL(
            path: "/v1/text-to-speech/\(encodedVoiceID)",
            queryItems: [URLQueryItem(name: "output_format", value: request.outputFormat)]
        )
        let body = try makeSpeechBody(request)
        var urlRequest = try makeRequest(url: url, method: "POST", accept: audioAcceptHeader(for: request.outputFormat))
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await perform(urlRequest, context: .speech(voiceID: request.voiceID))
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }
        guard !data.isEmpty else {
            throw ElevenLabsError.malformedResponse("The audio response was empty.")
        }
        guard let contentType = normalizedContentType(httpResponse), isAudioContentType(contentType) else {
            throw ElevenLabsError.invalidAudioContentType(normalizedContentType(httpResponse))
        }

        return SynthesizedAudio(
            data: data,
            contentType: contentType,
            requestID: safeHeaderValue(httpResponse, field: "request-id"),
            traceID: safeHeaderValue(httpResponse, field: "x-trace-id"),
            characterCost: httpResponse.value(forHTTPHeaderField: "character-cost").flatMap(Int.init)
        )
    }

    private var hasUsableAPIKey: Bool {
        !apiKey.isEmpty && apiKey.count <= 512 && apiKey.unicodeScalars.allSatisfy {
            $0.value >= 0x21 && $0.value <= 0x7E
        }
    }

    private enum RequestContext {
        case voices
        case speech(voiceID: String)

        var isSpeech: Bool {
            if case .speech = self { return true }
            return false
        }
    }

    private func perform(_ request: URLRequest, context: RequestContext) async throws -> (Data, URLResponse) {
        do {
            // URLRequest.timeoutInterval is an inactivity timeout. Keep a
            // separate total deadline so a peer cannot keep this task alive
            // forever by sending a trickle of bytes. Cancellation of the
            // transport child also cancels URLSession's underlying task in
            // the production transport.
            let result = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { [transport, maximumResponseBytes] in
                    try await transport.data(for: request, maximumBytes: maximumResponseBytes)
                }
                group.addTask { [requestTimeout] in
                    try await Task.sleep(for: .seconds(requestTimeout))
                    throw ElevenLabsError.timeout
                }
                defer { group.cancelAll() }
                guard let first = try await group.next() else {
                    throw ElevenLabsError.timeout
                }
                return first
            }
            try Task.checkCancellation()
            guard result.0.count <= maximumResponseBytes else {
                throw ElevenLabsError.responseTooLarge(maximumBytes: maximumResponseBytes)
            }
            guard let responseURL = result.1.url else {
                throw ElevenLabsError.invalidResponse
            }
            if !sameOrigin(responseURL, baseURL) {
                throw ElevenLabsError.redirectRefused
            }
            if let httpResponse = result.1 as? HTTPURLResponse {
                if (300..<400).contains(httpResponse.statusCode) {
                    throw ElevenLabsError.redirectRefused
                }
                if !(200..<300).contains(httpResponse.statusCode) {
                    throw providerHTTPError(httpResponse, data: result.0, context: context)
                }
            }
            return result
        } catch let error as ElevenLabsError {
            throw error
        } catch let error as ElevenLabsTransportError {
            switch error {
            case let .responseTooLarge(maximumBytes):
                throw ElevenLabsError.responseTooLarge(maximumBytes: maximumBytes)
            case .timedOut:
                throw ElevenLabsError.timeout
            case .redirectRefused:
                throw ElevenLabsError.redirectRefused
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ElevenLabsError.timeout
        } catch let error as URLError {
            throw ElevenLabsError.network(code: error.errorCode)
        } catch {
            throw ElevenLabsError.network(code: -1)
        }
    }

    private func makeRequest(url: URL, method: String, accept: String) throws -> URLRequest {
        guard isValidBaseURL else { throw ElevenLabsError.invalidEndpoint }
        guard requestTimeout.isFinite, (1...600).contains(requestTimeout), maximumResponseBytes > 0 else {
            throw ElevenLabsError.invalidRequest("ElevenLabs client limits are invalid.")
        }
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard isValidBaseURL,
              path.hasPrefix("/"),
              let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ElevenLabsError.invalidEndpoint
        }
        var components = baseComponents
        let prefix = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([prefix, cleanPath].filter { !$0.isEmpty }.joined(separator: "/"))
        components.queryItems = queryItems
        components.fragment = nil
        guard let url = components.url else { throw ElevenLabsError.invalidEndpoint }
        return url
    }

    private var isValidBaseURL: Bool {
        guard baseURL.scheme?.lowercased() == "https",
              let host = baseURL.host, !host.isEmpty,
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil else { return false }
        return true
    }

    private func normalizedPageToken(_ token: String?) throws -> String? {
        guard let token else { return nil }
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 4_096,
              normalized.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ElevenLabsError.invalidRequest("The ElevenLabs page token is invalid.")
        }
        return normalized
    }

    private func makeSpeechBody(_ request: SpeechRequest) throws -> Data {
        let payload = SpeechPayload(request: request)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(payload)
        } catch {
            throw ElevenLabsError.invalidRequest("The narration request could not be encoded.")
        }
    }

    private struct SpeechPayload: Encodable {
        let text: String
        let modelID: String
        let languageCode: String?
        let voiceSettings: VoiceSettings?

        init(request: SpeechRequest) {
            text = request.text
            modelID = request.modelID
            languageCode = request.languageCode
            voiceSettings = request.voiceSettings
        }

        private enum CodingKeys: String, CodingKey {
            case text
            case modelID = "model_id"
            case languageCode = "language_code"
            case voiceSettings = "voice_settings"
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(text, forKey: .text)
            try values.encode(modelID, forKey: .modelID)
            try values.encodeIfPresent(languageCode, forKey: .languageCode)
            try values.encodeIfPresent(voiceSettings, forKey: .voiceSettings)
        }
    }

    private func providerHTTPError(_ response: HTTPURLResponse, data: Data, context: RequestContext) -> ElevenLabsError {
        let details = parseProviderError(data)
        let normalizedStatus = details.status?.lowercased() ?? ""
        let normalizedMessage = details.message?.lowercased() ?? ""
        let combined = normalizedStatus + " " + normalizedMessage
        let kind: ElevenLabsHTTPErrorKind
        if let providerKind = classifyProviderError(combined), !(500...599).contains(response.statusCode) {
            // ElevenLabs uses a structured status in some 401 responses for
            // exhausted credits. Prefer that detail over the HTTP status so a
            // user can fix quota instead of replacing a valid API key.
            kind = providerKind
        } else {
            switch response.statusCode {
            case 401, 403:
                kind = .authentication
            case 402:
                kind = .quota
            case 429:
                kind = .rateLimit
            case 404:
                kind = context.isSpeech ? .voice : .notFound
            case 500...599:
                kind = .server
            case 422, 400...499:
                kind = .validation
            default:
                kind = .unknown
            }
        }
        return .http(statusCode: response.statusCode, kind: kind, message: sanitizeProviderMessage(details.message))
    }

    private func classifyProviderError(_ text: String) -> ElevenLabsHTTPErrorKind? {
        if text.contains("invalid_api_key") || text.contains("authentication") || text.contains("unauthorized") {
            return .authentication
        }
        if text.contains("quota") || text.contains("insufficient_credit") ||
            text.contains("credit_exhausted") || text.contains("character_limit") ||
            text.contains("max_character") {
            return .quota
        }
        if text.contains("rate_limit") || text.contains("too_many_requests") || text.contains("rate limited") {
            return .rateLimit
        }
        if text.contains("voice_not_found") || text.contains("unsupported_voice") ||
            text.contains("voice") && (text.contains("not found") || text.contains("unavailable") || text.contains("unsupported")) {
            return .voice
        }
        if text.contains("language") || text.contains("locale") {
            return .language
        }
        if text.contains("model") && (text.contains("not") || text.contains("support") || text.contains("unavailable")) {
            return .model
        }
        return nil
    }

    private struct ProviderErrorDetails {
        let status: String?
        let message: String?
    }

    private func parseProviderError(_ data: Data) -> ProviderErrorDetails {
        let bounded = data.prefix(64 * 1024)
        guard let object = try? JSONSerialization.jsonObject(with: bounded),
              let dictionary = object as? [String: Any] else {
            return ProviderErrorDetails(status: nil, message: nil)
        }
        let detail = dictionary["detail"] as? [String: Any] ?? dictionary
        return ProviderErrorDetails(
            status: detail["status"] as? String,
            message: detail["message"] as? String
        )
    }

    private func sanitizeProviderMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        var sanitized = value.replacingOccurrences(of: apiKey, with: "[redacted]")
        sanitized = sanitized.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        sanitized = sanitized.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !sanitized.isEmpty else { return nil }
        return String(sanitized.prefix(240))
    }

    private func normalizedContentType(_ response: HTTPURLResponse) -> String? {
        guard let rawValue = response.value(forHTTPHeaderField: "Content-Type") else {
            return nil
        }
        let value = rawValue
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let value, value.count <= 128,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }

    private func safeHeaderValue(_ response: HTTPURLResponse, field: String) -> String? {
        guard let value = response.value(forHTTPHeaderField: field),
              value.count <= 256,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return value
    }

    private func isJSONContentType(_ value: String) -> Bool {
        value == "application/json" || value.hasSuffix("+json")
    }

    private func isAudioContentType(_ value: String) -> Bool {
        value == "audio/mpeg" || value == "audio/mp3" || value == "audio/wav" || value == "audio/wave" ||
            value == "audio/x-wav" || value == "audio/pcm" || value == "audio/l16" || value == "audio/ogg" ||
            value == "audio/opus" || value == "audio/basic" || value == "audio/webm"
    }

    private func audioAcceptHeader(for outputFormat: String) -> String {
        if outputFormat.hasPrefix("mp3_") { return "audio/mpeg" }
        if outputFormat.hasPrefix("pcm_") { return "audio/pcm" }
        if outputFormat.hasPrefix("opus_") { return "audio/opus" }
        return "audio/*"
    }

    private func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsScheme = lhs.scheme?.lowercased(),
              let rhsScheme = rhs.scheme?.lowercased(),
              let lhsHost = lhs.host?.lowercased(),
              let rhsHost = rhs.host?.lowercased() else { return false }
        return lhsScheme == rhsScheme && lhsHost == rhsHost && effectivePort(lhs) == effectivePort(rhs)
    }

    private func effectivePort(_ url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "http" ? 80 : 443
    }
}
