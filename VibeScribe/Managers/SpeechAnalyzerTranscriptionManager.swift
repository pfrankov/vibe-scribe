//
//  SpeechAnalyzerTranscriptionManager.swift
//  VibeScribe
//
//  Manages on-device speech recognition using Apple's Speech framework (macOS 26+).
//  Provides locale detection, audio format conversion, and asset management.
//

import Foundation
@preconcurrency import AVFoundation
#if canImport(Speech)
import Speech
#endif

final class SpeechAnalyzerTranscriptionManager {
    static let shared = SpeechAnalyzerTranscriptionManager()
    
    private init() {}
    
    func isSupported() -> Bool {
        if #available(macOS 26, *) {
            #if canImport(Speech)
            return true
            #else
            return false
            #endif
        } else {
            return false
        }
    }
    
    /// Transcribes audio file using on-device Speech framework.
    /// - Parameters:
    ///   - url: Audio file URL to transcribe
    ///   - locale: Optional locale override; auto-detects if nil
    /// - Returns: Transcribed text
    /// - Throws: TranscriptionError if transcription fails or system is incompatible
    func transcribeAudio(at url: URL, locale: Locale? = nil) async throws -> String {
        guard #available(macOS 26, *) else {
            throw TranscriptionError.featureUnavailable
        }
        
        #if canImport(Speech)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TranscriptionError.invalidAudioFile
        }
        
        Logger.debug("Starting native transcription for \(url.lastPathComponent)", category: .transcription)
        
        try await ensureAuthorization()
        
        // Determine locale: user-selected > auto-detected > current
        let candidateLocale: Locale
        if let explicitLocale = locale {
            candidateLocale = explicitLocale
            Logger.debug("Using user-selected locale \(explicitLocale.identifier)", category: .transcription)
        } else {
            candidateLocale = await detectPreferredLocale(for: url, fallback: Locale.current)
        }
        let resolvedLocale = await resolveSupportedLocale(candidateLocale)
        Logger.debug("Resolved locale: \(resolvedLocale.identifier)", category: .transcription)
        
        let transcriber = Speech.SpeechTranscriber(locale: resolvedLocale, preset: .transcription)
        try await ensureSpeechAssets(for: transcriber, locale: resolvedLocale)
        
        // Prepare compatible audio file
        let preparedFileURL = try await prepareCompatibleAudioFile(at: url, for: transcriber)
        defer { try? FileManager.default.removeItem(at: preparedFileURL) }
        
        let preparedAudioFile = try AVAudioFile(forReading: preparedFileURL)
        
        // Reserve speech assets (best effort, not critical)
        let assetReservation = try? await reserveAssets(for: resolvedLocale)
        defer {
            if let assetReservation {
                Task { await assetReservation.release() }
            }
        }
        
        let analyzer: Speech.SpeechAnalyzer
        do {
            analyzer = try await Speech.SpeechAnalyzer(inputAudioFile: preparedAudioFile, modules: [transcriber], finishAfterFile: true)
        } catch {
            Logger.error("Failed to start SpeechAnalyzer.", error: error, category: .transcription)
            throw TranscriptionError.processingFailed(error.localizedDescription)
        }
        
        var didFinishAnalyzer = false
        defer {
            if !didFinishAnalyzer {
                Task {
                    await analyzer.cancelAndFinishNow()
                }
            }
        }
        
        var fragments: [(Double, String)] = []
        
        do {
            for try await result in transcriber.results {
                guard result.isFinal else { continue }
                
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                
                let startTime = result.range.start.seconds.isFinite ? result.range.start.seconds : Double(fragments.count)
                fragments.append((startTime, text))
            }
        } catch {
            Logger.error("Error while reading SpeechTranscriber results.", error: error, category: .transcription)
            throw TranscriptionError.processingFailed(error.localizedDescription)
        }
        
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            didFinishAnalyzer = true
        } catch {
            Logger.error("Failed to finalize SpeechAnalyzer.", error: error, category: .transcription)
            throw TranscriptionError.processingFailed(error.localizedDescription)
        }
        
        guard !fragments.isEmpty else {
            Logger.warning("Native transcription produced no final segments.", category: .transcription)
            return ""
        }
        
        let combined = fragments
            .sorted(by: { $0.0 < $1.0 })
            .map(\.1)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        Logger.info("Native transcription finished with \(combined.count) characters.", category: .transcription)
        return combined
        #else
        throw TranscriptionError.engineUnavailable
        #endif
    }
    
    @available(macOS 26, *)
    private func resolveSupportedLocale(_ locale: Locale) async -> Locale {
        // supportedLocale may or may not throw depending on implementation
        if let equivalent = try? await Speech.SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return equivalent
        }
        
        let supported = await Speech.SpeechTranscriber.supportedLocales
        let canonicalTarget = canonicalIdentifier(for: locale.identifier)
        
        if let exactMatch = supported.first(where: { canonicalIdentifier(for: $0.identifier) == canonicalTarget }) {
            return exactMatch
        }
        
        if let languageCode = locale.language.languageCode?.identifier {
            if let languageMatch = supported.first(where: { $0.language.languageCode?.identifier == languageCode }) {
                return languageMatch
            }
        }
        
        if let englishFallback = supported.first(where: { $0.language.languageCode?.identifier == "en" }) {
            return englishFallback
        }
        
        return supported.first ?? locale
    }
    
    @available(macOS 26, *)
    private func ensureAuthorization() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .denied, .restricted:
            Logger.warning("Speech recognition authorization denied or restricted.", category: .transcription)
            throw TranscriptionError.permissionDenied
        case .notDetermined:
            let status = await requestAuthorization()
            switch status {
            case .authorized:
                return
            case .denied, .restricted:
                Logger.warning("Speech recognition authorization denied after request.", category: .transcription)
                throw TranscriptionError.permissionDenied
            case .notDetermined:
                Logger.warning("Speech recognition authorization remained undetermined.", category: .transcription)
                throw TranscriptionError.permissionDenied
            @unknown default:
                Logger.warning("Speech recognition authorization returned unknown status.", category: .transcription)
                throw TranscriptionError.permissionDenied
            }
        @unknown default:
            Logger.warning("Speech recognition authorization returned unknown default status.", category: .transcription)
            throw TranscriptionError.permissionDenied
        }
    }
    
    @available(macOS 26, *)
    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    @available(macOS 26, *)
    private func detectPreferredLocale(for url: URL, fallback: Locale) async -> Locale {
        let asset = AVURLAsset(url: url)
        
        do {
            let trackCodes = try await extractLanguageCodesFromTracks(asset: asset)
            for candidate in trackCodes {
                guard let canonicalIdentifier = canonicalIdentifier(for: candidate) else { continue }
                let candidateLocale = Locale(identifier: canonicalIdentifier)
                Logger.debug("Detected audio track locale: \(candidateLocale.identifier)", category: .transcription)
                return candidateLocale
            }
        } catch {
            Logger.debug("Could not detect locale from audio metadata: \(error.localizedDescription)", category: .transcription)
        }
        
        Logger.debug("Using fallback locale: \(fallback.identifier)", category: .transcription)
        return fallback
    }
    
    @available(macOS 26, *)
    @preconcurrency
    private func extractLanguageCodesFromTracks(asset: AVURLAsset) async throws -> [String] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return [] }
        
        var codes: [String] = []
        
        // macOS 26 always has macOS 13+ APIs available
        if let extendedTag = try? await track.load(.extendedLanguageTag), !extendedTag.isEmpty {
            codes.append(extendedTag)
        }
        if let languageCode = try? await track.load(.languageCode), !languageCode.isEmpty {
            codes.append(languageCode)
        }
        
        return codes
    }
    
    private func canonicalIdentifier(for identifier: String) -> String? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let replaced = trimmed.replacingOccurrences(of: "_", with: "-")
        let canonical = Locale.canonicalLanguageIdentifier(from: replaced)
        return canonical.isEmpty ? replaced : canonical
    }
    
    @available(macOS 26, *)
    private func ensureSpeechAssets(for transcriber: Speech.SpeechTranscriber, locale: Locale) async throws {
        #if canImport(Speech)
        let modules: [any Speech.SpeechModule] = [transcriber]
        let status = await Speech.AssetInventory.status(forModules: modules)
        
        switch status {
        case .unsupported:
            Logger.warning("Speech assets unsupported for locale \(locale.identifier).", category: .transcription)
            throw TranscriptionError.engineUnavailable
        case .supported, .installed:
            break
        case .downloading:
            Logger.info("Speech assets are downloading for locale \(locale.identifier), awaiting completion.", category: .transcription)
        @unknown default:
            Logger.warning("Encountered unknown asset status for locale \(locale.identifier).", category: .transcription)
        }
        
        #if compiler(>=5.3)
        if let request = try? await Speech.AssetInventory.assetInstallationRequest(supporting: modules) {
            Logger.info("Downloading speech assets for locale \(locale.identifier).", category: .transcription)
            do {
                try await request.downloadAndInstall()
            } catch {
                Logger.error("Failed to download speech assets.", error: error, category: .transcription)
                throw TranscriptionError.processingFailed(error.localizedDescription)
            }
        }
        #endif
        #endif
    }
    
    @available(macOS 26, *)
    @preconcurrency
    private func prepareCompatibleAudioFile(at url: URL, for transcriber: Speech.SpeechTranscriber) async throws -> URL {
        let sourceAsset = AVURLAsset(url: url)
        let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        
        guard !audioTracks.isEmpty else {
            throw TranscriptionError.invalidAudioFile
        }
        
        let supportedFormats = await transcriber.availableCompatibleAudioFormats
        let sourceFile = try AVAudioFile(forReading: url)
        
        let targetFormat = await Speech.SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: sourceFile.processingFormat
        ) ?? supportedFormats.first ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetFormat.sampleRate,
            AVNumberOfChannelsKey: Int(targetFormat.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let reader = try AVAssetReader(asset: sourceAsset)
        guard let audioTrack = audioTracks.first else {
            throw TranscriptionError.invalidAudioFile
        }
        
        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else {
            throw TranscriptionError.processingFailed(
                AppLanguage.localized("unable.to.configure.audio.reader")
            )
        }
        reader.add(trackOutput)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-transcription-\(UUID().uuidString)-\(ProcessInfo.processInfo.processIdentifier)")
            .appendingPathExtension("caf")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw TranscriptionError.processingFailed(
                AppLanguage.localized("unable.to.configure.audio.writer")
            )
        }
        writer.add(writerInput)
        
        guard reader.startReading() else {
            throw reader.error ?? TranscriptionError.processingFailed(
                AppLanguage.localized("failed.to.start.audio.reader")
            )
        }
        guard writer.startWriting() else {
            throw writer.error ?? TranscriptionError.processingFailed(
                AppLanguage.localized("failed.to.start.audio.writer")
            )
        }
        writer.startSession(atSourceTime: .zero)
        
        nonisolated(unsafe) let unsafeWriter = writer
        nonisolated(unsafe) let unsafeReader = reader
        nonisolated(unsafe) let unsafeWriterInput = writerInput
        nonisolated(unsafe) let unsafeTrackOutput = trackOutput
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "native.transcription.audio.convert")
            unsafeWriterInput.requestMediaDataWhenReady(on: queue) {
                while unsafeWriterInput.isReadyForMoreMediaData {
                    if let buffer = unsafeTrackOutput.copyNextSampleBuffer() {
                        if !unsafeWriterInput.append(buffer) {
                            unsafeReader.cancelReading()
                            unsafeWriter.cancelWriting()
                            continuation.resume(
                                throwing: unsafeWriter.error ?? TranscriptionError.processingFailed(
                                    AppLanguage.localized("failed.to.append.audio.sample.buffer")
                                )
                            )
                            return
                        }
                    } else {
                        unsafeWriterInput.markAsFinished()
                        unsafeWriter.finishWriting {
                            if let error = unsafeWriter.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: ())
                            }
                        }
                        break
                    }
                }
            }
        }
        
        if reader.status != .completed {
            throw reader.error ?? TranscriptionError.processingFailed(
                AppLanguage.localized("audio.conversion.did.not.complete")
            )
        }
        
        return outputURL
    }
    
    @available(macOS 26, *)
    private func reserveAssets(for locale: Locale) async throws -> SpeechAssetReservation? {
        do {
            let didReserve = try await Speech.AssetInventory.reserve(locale: locale)
            return SpeechAssetReservation(locale: locale, didReserve: didReserve)
        } catch {
            return nil
        }
    }
}

@available(macOS 26, *)
private struct SpeechAssetReservation {
    let locale: Locale
    let didReserve: Bool
    
    func release() async {
        guard didReserve else { return }
        await Speech.AssetInventory.release(reservedLocale: locale)
    }
}
