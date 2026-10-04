#!/usr/bin/env python3
"""Extract production request/routing code for the isolated privacy regression.

The same extraction is applied to baseline and candidate. SwiftData's model
macro/import are removed for this Foundation-only harness; local engines and
persistence are stubbed. The production summary helpers, provider-selection
block, regular-request construction, and multipart builder remain unchanged.
Only transport dispatch and the Combine-to-async bridge are adapted. Every
request is captured and rewritten to a non-network scheme by the Swift probe.
This does not exercise real speech engines, permission prompts, or SwiftData.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
IMPORTS = "import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n"


def section(text, start, end, end_count=1):
    for marker, expected in ((start, 1), (end, end_count)):
        count = text.count(marker)
        if count != expected:
            raise SystemExit(f"Expected {expected} extraction marker(s) {marker!r}, found {count}")
    begin = text.index(start)
    finish = text.index(end, begin)
    return text[begin:finish]


def replace_once(text, old, new):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected one substitution {old!r}, found {count}")
    return text.replace(old, new, 1)


def main():
    output = Path(sys.argv[1])
    source_ref = sys.argv[2] if len(sys.argv) > 2 else ""
    paths = [
        "VibeScribe/Models/AppSettings.swift",
        "VibeScribe/Managers/RecordProcessingManager.swift",
        "VibeScribe/Managers/WhisperTranscriptionManager.swift",
        "VibeScribe/Utils/TextChunker.swift",
        "VibeScribe/Utils/URLBuilder.swift",
        "VibeScribe/Utils/SecurityUtils.swift",
    ]
    sources = {}
    for path in paths:
        raw = subprocess.check_output(["git", "show", f"{source_ref}:{path}"], cwd=ROOT) if source_ref else (ROOT / path).read_bytes()
        sources[path] = raw.decode("utf-8")

    model = replace_once(sources[paths[0]], "import SwiftData\n", "")
    model = replace_once(model, "@Model\n", "")
    manager, whisper = sources[paths[1]], sources[paths[2]]
    snapshot = section(manager, "    struct SettingsSnapshot: Equatable {", "    private enum Operation")
    errors = section(manager, "    private enum RecordProcessingError: LocalizedError {", "    // MARK: - Singleton")
    errors = replace_once(errors, "private enum RecordProcessingError", "enum RecordProcessingError")
    transcription_errors = section(whisper, "enum TranscriptionError: LocalizedError {", "// Structure for real-time transcription updates")
    # Include validation helpers added anywhere between generateSummary and Helpers.
    summary_helpers = section(manager, "    private func generateSummary(for text: String, job: ProcessingJob)", "    // MARK: - Helpers")
    summary_helpers = replace_once(summary_helpers, "URLSession.shared.data(for: request)", "CaptureSession.data(for: request)")
    multipart = section(whisper, "    private func buildMultipartRequest(", "    // MARK: SRT text extraction")
    route = section(manager, "            let transcriptionText: String", "            let trimmed = transcriptionText.trimmingCharacters", end_count=2)
    preflight = section(manager, "        let fallbackBaseURL = job.settings.resolvedWhisperBaseURL.trimmingCharacters", "        var didResume = false")

    # Keep actual non-streaming provider/model resolution and all request fields.
    regular_call = section(whisper, "        if !useStreaming {", "        let serverKey = settings.resolvedWhisperBaseURL")
    regular_call = replace_once(regular_call, "return transcribeRegular(", "return try await transcribeRegular(")
    regular = section(whisper, "    private func transcribeRegular(", "    // MARK: Streaming transcription")
    regular_prefix = section(regular, "        guard let serverURL =", "            return urlSession.dataTaskPublisher(for: request)")
    # Adapt only Combine's early failure return and dispatch; retain request setup.
    regular_prefix = replace_once(regular_prefix,
        'return Fail(error: .networkError(NSError(domain: "InvalidURL", code: -1))).eraseToAnyPublisher()',
        'throw TranscriptionError.networkError(NSError(domain: "InvalidURL", code: -1))')

    (output / "SourceParts.swift").write_text(IMPORTS + "\n".join([
        model, sources[paths[3]], sources[paths[4]], sources[paths[5]], transcription_errors,
    ]))
    (output / "PipelineParts.swift").write_text(IMPORTS + snapshot + errors + """
struct ProcessingJob { let settings: SettingsSnapshot; let modelContext = ModelContext() }
@MainActor final class Harness {
""" + summary_helpers + multipart + """
    var nativeError: Error?
    var defaultError: Error?
    func summary(_ text: String, settings: AppSettings) async throws -> String {
        try await generateSummary(for: text, job: ProcessingJob(settings: SettingsSnapshot(settings: settings)))
    }
    func title(_ text: String, record: Record, settings: AppSettings) async {
        await maybeGenerateTitle(for: record, summary: text, job: ProcessingJob(settings: SettingsSnapshot(settings: settings)))
    }
    func route(settings: AppSettings, fileURL: URL, preferStreaming: Bool = false) async throws -> String {
        let job = ProcessingJob(settings: SettingsSnapshot(settings: settings))
""" + route + """
        return transcriptionText
    }
    private func performDefaultTranscription(fileURL: URL) async throws -> String {
        if let defaultError { throw defaultError }
        return "SYNTHETIC_DEFAULT_TRANSCRIPT"
    }
    private func performSpeechAnalyzerTranscription(fileURL: URL, locale: Locale?) async throws -> String {
        if let nativeError { throw nativeError }
        return "SYNTHETIC_NATIVE_TRANSCRIPT"
    }
    private func attemptStreamingTranscription(job: ProcessingJob, fileURL: URL) async throws -> String {
        fatalError("Streaming is outside this fixture")
    }
    private func performRegularTranscription(job: ProcessingJob, fileURL: URL) async throws -> String {
""" + preflight + """
        return try await nonStreamingTranscription(audioURL: fileURL, settings: settingsModel, useStreaming: false)
    }
    private func nonStreamingTranscription(audioURL: URL, settings: AppSettings, useStreaming: Bool) async throws -> String {
""" + regular_call + """
        fatalError("Streaming is outside this fixture")
    }
    private func transcribeRegular(audioURL: URL, baseURL: String, apiKey: String, model: String, responseFormat: String) async throws -> String {
""" + regular_prefix + """
            let (data, response) = try await CaptureSession.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw TranscriptionError.serverError("SYNTHETIC_HTTP_FAILURE")
            }
            return String(data: data, encoding: .utf8)!
        } catch {
            throw error
        }
    }
}
""")
    manifest = {path: hashlib.sha256(text.encode()).hexdigest() for path, text in sources.items()}
    manifest["source_ref"] = source_ref or "working-tree"
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared exact-count production extractions from {source_ref or 'working tree'}", flush=True)


if __name__ == "__main__":
    main()
