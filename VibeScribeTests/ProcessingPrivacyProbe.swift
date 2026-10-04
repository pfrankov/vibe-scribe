import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Foundation-only dependencies for the extracted production helpers. These do
// not simulate real permission prompts, persistence, recognition, or decoding.
struct AppLanguage {
    static func localized(_ key: String) -> String {
        ["http.error.from.llm.server.arg1": "HTTP %d",
         "error.summarizing.chunk.arg1.arg2": "Chunk %d: %@"][key] ?? key
    }
    static func localized(_ key: String, comment: StaticString) -> String { localized(key) }
}
enum LogCategory { case llm, transcription, security }
struct Logger {
    static func info(_ message: String, category: LogCategory) {}
    static func debug(_ message: String, category: LogCategory) {}
    static func warning(_ message: String, category: LogCategory) {}
    static func error(_ message: String, error: Error? = nil, category: LogCategory) {}
}
struct UITestMockPipeline {
    static var isEnabled = false
    static var summaryCalls = 0
    static func sleepForProcessingStep() async throws {}
    static func summaryText(model: String, transcription: String) throws -> String {
        summaryCalls += 1
        return "SYNTHETIC_MOCK_SUMMARY"
    }
}
final class ModelContext { func save() throws {} }
final class Record { var name = "SYNTHETIC_RECORD" }

// Fail closed: the original URL never reaches URLSession. The custom scheme
// cannot use the built-in HTTP transport even if protocol registration fails.
final class SinkProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handled = 0
    static func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return handled
    }
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "vibescribe-audit"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url?.scheme == "vibescribe-audit")
        Self.lock.lock()
        Self.handled += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 401,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("SYNTHETIC_UNAUTHORIZED".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor enum CaptureSession {
    static var requests: [URLRequest] = []
    static var totalRequests = 0
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SinkProtocol.self]
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()
    static func data(for original: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(original)
        totalRequests += 1
        var intercepted = original
        var components = URLComponents(url: original.url!, resolvingAgainstBaseURL: false)!
        components.scheme = "vibescribe-audit"
        intercepted.url = components.url!
        precondition(intercepted.url?.scheme == "vibescribe-audit")
        return try await session.data(for: intercepted)
    }
}

@main struct ProcessingPrivacyProbe {
    private static let configurationErrorKey = "choose.a.summary.model.and.a.valid.http.or.https.endpoint.in.settings"
    private static let transcript = "SYNTHETIC_TRANSCRIPT_MARKER"
    private static let summary = "SYNTHETIC_SUMMARY_MARKER"
    private static let audio = Data("SYNTHETIC_AUDIO_FILE_MARKER".utf8)

    @MainActor static func main() async throws {
        precondition(CommandLine.arguments.count >= 2)
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        try audio.write(to: file)
        let legacy = CommandLine.arguments.contains("--expect-legacy-dispatch")
        let harness = Harness()

        try await checkUnconfiguredSummaryAndTitle(harness, legacy: legacy)
        try await checkNativeRouting(harness, file: file, legacy: legacy)
        try await checkConfiguredDestinations(harness, file: file)
        if !legacy {
            try await checkInvalidConfiguration(harness)
            try await checkMockIsolation(harness)
        }
        precondition(CaptureSession.totalRequests > 0, "Positive request controls must execute")
        precondition(SinkProtocol.count() == CaptureSession.totalRequests,
                     "Every dispatched request must be handled in process")
        print("PASS: \(SinkProtocol.count()) dispatches intercepted on a non-network scheme; no external destination used")
        print("Scope: extracted request/routing code; stubbed engines/persistence; no real permission prompt or full app pipeline")
    }

    @MainActor private static func failure(_ action: () async throws -> String) async -> Error {
        do {
            _ = try await action()
            fatalError("Expected a local or synthetic HTTP failure")
        } catch {
            return error
        }
    }

    @MainActor private static func checkUnconfiguredSummaryAndTitle(_ harness: Harness, legacy: Bool) async throws {
        for model in ["", " \t\n"] {
            for chunking in [true, false] {
                let settings = AppSettings()
                precondition(settings.whisperProvider == .defaultProvider)
                settings.openAIModel = model
                settings.useChunking = chunking
                CaptureSession.requests = []
                let error = await failure { try await harness.summary(transcript, settings: settings) }
                if legacy {
                    precondition(error.localizedDescription.contains("401"))
                    try verifyChatRequest(url: "https://api.openai.com/v1/chat/completions", marker: transcript, model: model)
                } else {
                    precondition(error.localizedDescription == configurationErrorKey,
                                 "Configuration errors must precede chunk wrapping")
                    precondition(CaptureSession.requests.isEmpty, "Unconfigured summary must not dispatch")
                }
                CaptureSession.requests = []
                let record = Record()
                await harness.title(summary, record: record, settings: settings)
                precondition(record.name == "SYNTHETIC_RECORD")
                if legacy {
                    try verifyChatRequest(url: "https://api.openai.com/v1/chat/completions", marker: summary, model: model)
                } else {
                    precondition(CaptureSession.requests.isEmpty, "Unconfigured title must not dispatch")
                }
            }
        }
        print(legacy
              ? "REPRODUCED: blank/whitespace model summary and title reach dispatch before synthetic 401"
              : "PASS: blank/whitespace model blocks chunked/unchunked summary and direct title before dispatch")
    }

    @MainActor private static func checkNativeRouting(_ harness: Harness, file: URL, legacy: Bool) async throws {
        let failures: [(String, Error)] = [
            ("permissionDenied", TranscriptionError.permissionDenied),
            ("engineUnavailable", TranscriptionError.engineUnavailable),
            ("unexpected", NSError(domain: "SyntheticNative", code: 7,
                                    userInfo: [NSLocalizedDescriptionKey: "SYNTHETIC_UNEXPECTED_NATIVE_FAILURE"])),
        ]
        for endpoint in ["https://api.openai.com/v1/", "http://127.0.0.1:9/v1/"] {
            for (name, nativeError) in failures {
                let settings = AppSettings()
                settings.whisperProvider = .speechAnalyzer
                precondition(settings.whisperProvider == .speechAnalyzer)
                settings.whisperBaseURL = endpoint
                harness.nativeError = nativeError
                CaptureSession.requests = []
                let error = await failure { try await harness.route(settings: settings, fileURL: file) }
                if legacy {
                    verifyAudioRequest(url: endpoint + "audio/transcriptions")
                } else {
                    precondition(CaptureSession.requests.isEmpty, "Native \(name) must not fall back")
                    precondition(error.localizedDescription == nativeError.localizedDescription,
                                 "Native failure should propagate rather than becoming a remote failure")
                }
            }
        }
        let settings = AppSettings()
        settings.whisperProvider = .speechAnalyzer
        settings.whisperBaseURL = ""
        CaptureSession.requests = []
        _ = await failure { try await harness.route(settings: settings, fileURL: file) }
        precondition(CaptureSession.requests.isEmpty)
        harness.nativeError = nil
        let nativeResult = try await harness.route(settings: settings, fileURL: file)
        precondition(nativeResult == "SYNTHETIC_NATIVE_TRANSCRIPT")
        precondition(CaptureSession.requests.isEmpty)
        settings.whisperProvider = .defaultProvider
        harness.defaultError = TranscriptionError.engineUnavailable
        _ = await failure { try await harness.route(settings: settings, fileURL: file) }
        precondition(CaptureSession.requests.isEmpty)
        harness.defaultError = nil
        print(legacy
              ? "REPRODUCED: Native permission/unavailable/unexpected failures dispatch to stored remote or local Whisper endpoint"
              : "PASS: Native permission/unavailable/unexpected failures never dispatch remote or local Whisper fallback")
        print("PASS: empty endpoint, Native success, and Default-provider failure controls")
    }

    @MainActor private static func checkConfiguredDestinations(_ harness: Harness, file: URL) async throws {
        for (rawEndpoint, endpoint) in [
            ("http://127.0.0.1:9/v1/", "http://127.0.0.1:9/v1/"),
            ("https://summary.example.invalid/v1/", "https://summary.example.invalid/v1/"),
            (" \nhttp://127.0.0.1:9/v1/\t", "http://127.0.0.1:9/v1/"),
        ] {
            let settings = AppSettings()
            settings.openAIBaseURL = rawEndpoint
            settings.openAIModel = "synthetic-model"
            for chunking in [true, false] {
                settings.useChunking = chunking
                CaptureSession.requests = []
                let error = await failure { try await harness.summary(transcript, settings: settings) }
                precondition(error.localizedDescription.contains("401"))
                try verifyChatRequest(url: endpoint + "chat/completions", marker: transcript, model: "synthetic-model")
            }
            CaptureSession.requests = []
            await harness.title(summary, record: Record(), settings: settings)
            try verifyChatRequest(url: endpoint + "chat/completions", marker: summary, model: "synthetic-model")
        }
        for endpoint in ["http://127.0.0.1:9/v1/", "https://transcription.example.invalid/v1/"] {
            let settings = AppSettings()
            settings.whisperProvider = .compatibleAPI
            settings.whisperBaseURL = endpoint
            CaptureSession.requests = []
            _ = await failure { try await harness.route(settings: settings, fileURL: file) }
            verifyAudioRequest(url: endpoint + "audio/transcriptions")
        }
        let settings = AppSettings()
        settings.whisperProvider = .whisperServer
        CaptureSession.requests = []
        _ = await failure { try await harness.route(settings: settings, fileURL: file) }
        verifyAudioRequest(url: "http://localhost:12017/v1/audio/transcriptions")
        print("PASS: configured keyless summary/title (including trimmed URL) and explicit local/remote transcription retain selected destinations")
    }

    @MainActor private static func checkInvalidConfiguration(_ harness: Harness) async throws {
        for endpoint in ["", " \t\n", "not a URL", "https://", "http:/v1", "ftp://example.invalid/v1/"] {
            let settings = AppSettings()
            settings.openAIBaseURL = endpoint
            settings.openAIModel = "synthetic-model"
            for chunking in [true, false] {
                settings.useChunking = chunking
                CaptureSession.requests = []
                let error = await failure { try await harness.summary(transcript, settings: settings) }
                precondition(error.localizedDescription == configurationErrorKey)
                await harness.title(summary, record: Record(), settings: settings)
                precondition(CaptureSession.requests.isEmpty, "Invalid endpoint must fail before dispatch")
            }
        }
        let settings = AppSettings()
        settings.chunkSize = 0
        CaptureSession.requests = []
        let error = await failure { try await harness.summary(transcript, settings: settings) }
        precondition(error.localizedDescription == "chunk.size.must.be.greater.than.zero.update.it.in.settings")
        precondition(CaptureSession.requests.isEmpty)
        print("PASS: invalid/unsupported endpoints block summary/title; invalid chunk-size precedence retained")
    }

    @MainActor private static func checkMockIsolation(_ harness: Harness) async throws {
        UITestMockPipeline.isEnabled = true
        defer { UITestMockPipeline.isEnabled = false }
        UITestMockPipeline.summaryCalls = 0
        CaptureSession.requests = []
        let settings = AppSettings()
        let error = await failure { try await harness.summary(transcript, settings: settings) }
        precondition(error.localizedDescription == configurationErrorKey)
        precondition(UITestMockPipeline.summaryCalls == 0, "Mock summary must not bypass configuration validation")
        settings.openAIModel = "synthetic-model"
        settings.openAIBaseURL = ""
        let endpointError = await failure { try await harness.summary(transcript, settings: settings) }
        precondition(endpointError.localizedDescription == configurationErrorKey)
        precondition(UITestMockPipeline.summaryCalls == 0, "Mock summary must not bypass endpoint validation")
        settings.openAIBaseURL = "https://summary.example.invalid/v1/"
        let result = try await harness.summary(transcript, settings: settings)
        precondition(result == "SYNTHETIC_MOCK_SUMMARY" && UITestMockPipeline.summaryCalls == 1)
        let record = Record()
        await harness.title(summary, record: record, settings: settings)
        precondition(record.name == "SYNTHETIC_RECORD", "Mock auto-title should retain the current name")
        precondition(CaptureSession.requests.isEmpty, "Mock summary/title must not dispatch")
        print("PASS: mock summary still validates configuration; mock auto-title preserves name without dispatch")
    }

    @MainActor private static func verifyChatRequest(url: String, marker: String, model: String) throws {
        precondition(CaptureSession.requests.count == 1)
        let request = CaptureSession.requests[0]
        precondition(request.url?.absoluteString == url)
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil, "Keyless endpoints must remain supported")
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["model"] as? String == model)
        let messages = body["messages"] as! [[String: Any]]
        precondition(messages[0]["role"] as? String == "user")
        precondition((messages[0]["content"] as! String).contains(marker))
    }

    @MainActor private static func verifyAudioRequest(url: String) {
        precondition(CaptureSession.requests.count == 1)
        let request = CaptureSession.requests[0]
        precondition(request.url?.absoluteString == url)
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        precondition(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        precondition(request.httpBody!.range(of: audio) != nil, "Complete synthetic file must be present")
        let body = String(data: request.httpBody!, encoding: .utf8)!
        precondition(body.contains("name=\"model\"\r\n\r\nwhisper-1\r\n"))
        precondition(body.contains("name=\"response_format\"\r\n\r\nsrt\r\n"))
    }
}
