//
//  AudioUtils.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 15.04.2025.
//

import Foundation
import AVFoundation

struct AudioUtils {
    
    // MARK: - Audio Merging
    
    /// Merges two audio files into one, overlaying them.
    /// - Parameters:
    ///   - micURL: URL of the microphone audio file
    ///   - systemURL: URL of the system audio file
    ///   - completion: Completion handler that returns the URL of the merged file or an error
    static func mergeAudioFiles(micURL: URL, systemURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        
        // Validate input files exist
        guard FileManager.default.fileExists(atPath: micURL.path) else {
            completion(.failure(AudioUtilsError.fileNotFound("Microphone audio file not found")))
            return
        }
        
        guard FileManager.default.fileExists(atPath: systemURL.path) else {
            completion(.failure(AudioUtilsError.fileNotFound("System audio file not found")))
            return
        }
        
        let composition = AVMutableComposition()
        
        // Create assets from URLs
        let micAsset = AVURLAsset(url: micURL)
        let systemAsset = AVURLAsset(url: systemURL)
        
        // Load tracks asynchronously (best practice)
        Task {
            do {
                // Load tracks for both assets
                guard let micAudioTrack = try await micAsset.loadTracks(withMediaType: .audio).first else {
                    throw AudioUtilsError.trackLoadingFailed("Could not load microphone audio track")
                }
                
                guard let systemAudioTrack = try await systemAsset.loadTracks(withMediaType: .audio).first else {
                    throw AudioUtilsError.trackLoadingFailed("Could not load system audio track")
                }
                
                // Create composition tracks
                guard let compositionMicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw AudioUtilsError.compositionFailed("Could not create microphone composition track")
                }
                
                guard let compositionSystemTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw AudioUtilsError.compositionFailed("Could not create system audio composition track")
                }
                
                // Determine the duration (use the longer of the two)
                let micDuration = try await micAsset.load(.duration)
                let systemDuration = try await systemAsset.load(.duration)
                let maxDuration = CMTimeMaximum(micDuration, systemDuration)
                let timeRange = CMTimeRange(start: .zero, duration: maxDuration)
                
                // Insert audio tracks into composition
                try compositionMicTrack.insertTimeRange(timeRange, of: micAudioTrack, at: .zero)
                try compositionSystemTrack.insertTimeRange(timeRange, of: systemAudioTrack, at: .zero)
                
                // Export the merged audio
                try await exportComposition(composition, completion: completion)
                
            } catch {
                Logger.error("Error during audio merging process", error: error, category: .audio)
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Audio Conversion
    
    /// Converts audio file to app's standard format (m4a)
    /// - Parameters:
    ///   - inputURL: URL of the input audio file
    ///   - completion: Completion handler that returns the URL of the converted file or an error
    static func convertAudioToStandardFormat(inputURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        Logger.info("Converting audio file to standard format: \(inputURL.lastPathComponent)", category: .audio)
        
        // Validate input file exists
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            completion(.failure(AudioUtilsError.fileNotFound("Input audio file not found")))
            return
        }
        
        let asset = AVURLAsset(url: inputURL)
        
        Task {
            do {
                // Check if file already has audio tracks
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                guard !audioTracks.isEmpty else {
                    throw AudioUtilsError.trackLoadingFailed("No audio tracks found in file")
                }
                
                // Generate unique output URL
                let timestamp = Int(Date().timeIntervalSince1970)
                let recordingsDir = try AudioUtils.getRecordingsDirectory()
                let outputURL = recordingsDir.appendingPathComponent("imported_\(timestamp).m4a")
                
                // Remove existing file if it exists
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                
                // Create export session
                guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                    throw AudioUtilsError.exportFailed("Could not create export session")
                }
                
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .m4a
                
                // Perform the export
                await exportSession.export()
                
                // Check export status
                switch exportSession.status {
                case .completed:
                    Logger.info("Audio conversion completed successfully: \(outputURL.path)", category: .audio)
                    completion(.success(outputURL))
                case .failed:
                    let error = exportSession.error ?? AudioUtilsError.exportFailed("Export session failed with unknown error")
                    Logger.error("Audio conversion failed", error: error, category: .audio)
                    completion(.failure(error))
                case .cancelled:
                    Logger.warning("Audio conversion cancelled", category: .audio)
                    completion(.failure(AudioUtilsError.exportCancelled))
                default:
                    completion(.failure(AudioUtilsError.exportFailed("Export session ended with unexpected status: \(exportSession.status)")))
                }
                
            } catch {
                Logger.error("Error during audio conversion process", error: error, category: .audio)
                completion(.failure(error))
            }
        }
    }
    
    /// Gets duration of audio file
    /// - Parameter url: URL of the audio file
    /// - Returns: Duration in seconds or 0 if unable to determine
    static func getAudioDuration(url: URL) -> TimeInterval {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.warning("Audio file not found for duration calculation: \(url.path)", category: .audio)
            return 0
        }
        
        let asset = AVURLAsset(url: url)
        
        // Synchronously read duration (macOS 12.3+)
        let duration: CMTime = asset.duration
        
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Validate duration is valid
        guard durationSeconds.isFinite && durationSeconds > 0 else {
            Logger.warning("Invalid duration for audio file: \(url.lastPathComponent)", category: .audio)
            return 0
        }
        
        return durationSeconds
    }
    
    /// Validates if a file is a valid audio file
    /// - Parameter url: URL of the file to validate
    /// - Returns: True if the file contains valid audio tracks
    static func isValidAudioFile(url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        
        let asset = AVURLAsset(url: url)
        
        do {
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return !audioTracks.isEmpty
        } catch {
            Logger.warning("Failed to validate audio file: \(url.lastPathComponent) - \(error.localizedDescription)", category: .audio)
            return false
        }
    }
    
    /// Gets the directory for storing recordings
    /// - Returns: URL to the recordings directory
    /// - Throws: AudioUtilsError if unable to create or access the directory
    static func getRecordingsDirectory() throws -> URL {
        // Prefer Application Support/<bundleID>/Recordings to avoid iCloud/backups and be consistent across app
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
            let base = appSupport.appendingPathComponent(bundleID, isDirectory: true)
            let dir = base.appendingPathComponent("Recordings", isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
                    Logger.info("Created recordings directory: \(dir.path)", category: .audio)
                } catch {
                    Logger.error("Failed to create recordings directory", error: error, category: .audio)
                    // fall back to Documents below
                }
            }
            if fm.fileExists(atPath: dir.path) {
                return dir
            }
        }
        
        // Fallback: Documents/<bundleID>/Recordings
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioUtilsError.exportFailed("Unable to access documents directory")
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
        let recordingsDirectory = documentsDirectory
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: recordingsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
                Logger.info("Created recordings directory: \(recordingsDirectory.path)", category: .audio)
            } catch {
                Logger.error("Failed to create recordings directory", error: error, category: .audio)
                throw AudioUtilsError.exportFailed("Failed to create recordings directory: \(error.localizedDescription)")
            }
        }
        return recordingsDirectory
    }
    
    // MARK: - Private Methods
    
    private static func exportComposition(_ composition: AVMutableComposition, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioUtilsError.exportFailed("Could not create export session")
        }
        
        // Generate unique output URL for merged file
        let timestamp = Int(Date().timeIntervalSince1970)
        let recordingsDir = try AudioUtils.getRecordingsDirectory()
        let outputURL = recordingsDir.appendingPathComponent("merged_\(timestamp).m4a")
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Configure export session
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        // Perform the export asynchronously
        await exportSession.export()
        
        // Check export status
        switch exportSession.status {
        case .completed:
            Logger.info("Audio merge completed successfully: \(outputURL.path)", category: .audio)
            completion(.success(outputURL))
        case .failed:
            let error = exportSession.error ?? AudioUtilsError.exportFailed("Export session failed with unknown error")
            Logger.error("Audio merge failed", error: error, category: .audio)
            completion(.failure(error))
        case .cancelled:
            Logger.warning("Audio merge cancelled", category: .audio)
            completion(.failure(AudioUtilsError.exportCancelled))
        default:
            completion(.failure(AudioUtilsError.exportFailed("Export session ended with unexpected status: \(exportSession.status)")))
        }
    }
}

// MARK: - Error Types

enum AudioUtilsError: LocalizedError {
    case fileNotFound(String)
    case trackLoadingFailed(String)
    case compositionFailed(String)
    case exportFailed(String)
    case exportCancelled
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let message):
            return "File not found: \(message)"
        case .trackLoadingFailed(let message):
            return "Track loading failed: \(message)"
        case .compositionFailed(let message):
            return "Composition failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        case .exportCancelled:
            return "Export was cancelled"
        }
    }
} 
