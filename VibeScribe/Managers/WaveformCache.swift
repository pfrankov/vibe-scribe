//
//  WaveformCache.swift
//  VibeScribe
//
//  Created by OpenAI on 2025-04-16.
//

import Foundation
import CryptoKit

/// Persists generated waveforms to disk so that subsequent loads can reuse cached data.
final class WaveformCache {
    static let shared = WaveformCache()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.vibescribe.waveform.cache", attributes: .concurrent)
    private let encoder: PropertyListEncoder
    private let decoder = PropertyListDecoder()

    private let cacheDirectory: URL
    private static let cacheVersion = 1

    private struct CachePayload: Codable {
        let version: Int
        let fileSize: UInt64
        let fileModificationDate: Date
        let duration: TimeInterval
        let sampleCount: Int
        let samples: [Float]
    }

    private struct FileMetadata {
        let size: UInt64
        let modificationDate: Date
    }

    private init() {
        encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        cacheDirectory = Self.makeCacheDirectory()
    }

    func cachedWaveform(for audioURL: URL) -> [Float]? {
        guard let metadata = fileMetadata(for: audioURL) else { return nil }
        let cacheURL = cacheFileURL(for: audioURL)

        return queue.sync {
            guard let payload = loadPayload(at: cacheURL) else { return nil }

            guard payload.version == Self.cacheVersion else {
                removeCacheFile(at: cacheURL)
                return nil
            }

            let modificationDelta = abs(payload.fileModificationDate.timeIntervalSince(metadata.modificationDate))
            guard payload.fileSize == metadata.size, modificationDelta < 1 else {
                return nil
            }

            return payload.samples
        }
    }

    func storeWaveform(_ samples: [Float], for audioURL: URL, duration: TimeInterval) {
        guard !samples.isEmpty else { return }
        guard let metadata = fileMetadata(for: audioURL) else { return }

        let payload = CachePayload(
            version: Self.cacheVersion,
            fileSize: metadata.size,
            fileModificationDate: metadata.modificationDate,
            duration: duration,
            sampleCount: samples.count,
            samples: samples
        )

        let cacheURL = cacheFileURL(for: audioURL)

        queue.async(flags: .barrier) { [cacheURL] in
            do {
                try self.ensureDirectoryExists(for: cacheURL)
                let data = try self.encoder.encode(payload)
                try data.write(to: cacheURL, options: [.atomic])
            } catch {
                Logger.error("Failed to store waveform cache", error: error, category: .data)
            }
        }
    }

    func clearCache(for audioURL: URL) {
        let cacheURL = cacheFileURL(for: audioURL)
        queue.async(flags: .barrier) { [cacheURL] in
            self.removeCacheFile(at: cacheURL)
        }
    }

    private func loadPayload(at url: URL) -> CachePayload? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return try decoder.decode(CachePayload.self, from: data)
        } catch {
            Logger.error("Failed to decode waveform cache payload", error: error, category: .data)
            removeCacheFile(at: url)
            return nil
        }
    }

    private func ensureDirectoryExists(for fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func removeCacheFile(at cacheURL: URL) {
        guard fileManager.fileExists(atPath: cacheURL.path) else { return }
        do {
            try fileManager.removeItem(at: cacheURL)
        } catch {
            Logger.error("Failed to remove waveform cache", error: error, category: .data)
        }
    }

    private static func makeCacheDirectory() -> URL {
        let baseURL: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseURL = appSupport.appendingPathComponent("VibeScribe", isDirectory: true)
        } else {
            baseURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("VibeScribe", isDirectory: true)
        }

        let cacheURL = baseURL.appendingPathComponent("WaveformCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            do {
                try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            } catch {
                Logger.error("Failed to create waveform cache directory", error: error, category: .data)
            }
        }
        return cacheURL
    }

    private func cacheFileURL(for audioURL: URL) -> URL {
        let fileName = Self.hash(for: audioURL)
        return cacheDirectory.appendingPathComponent(fileName).appendingPathExtension("waveform")
    }

    private static func hash(for url: URL) -> String {
        let identifier = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(identifier.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileMetadata(for audioURL: URL) -> FileMetadata? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: audioURL.path)
            guard let sizeNumber = attributes[.size] as? NSNumber else { return nil }
            guard let modificationDate = attributes[.modificationDate] as? Date else { return nil }
            return FileMetadata(size: sizeNumber.uint64Value, modificationDate: modificationDate)
        } catch {
            Logger.error("Failed to read waveform metadata", error: error, category: .data)
            return nil
        }
    }
}
