//
//  AudioUtils.swift
//  VibeScribe
//
//  Created by System on 15.04.2025.
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
    
    // MARK: - Private Methods
    
    private static func exportComposition(_ composition: AVMutableComposition, completion: @escaping (Result<URL, Error>) -> Void) async throws {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioUtilsError.exportFailed("Could not create export session")
        }
        
        // Generate unique output URL for merged file
        let timestamp = Int(Date().timeIntervalSince1970)
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioUtilsError.exportFailed("Could not access documents directory")
        }
        
        let outputURL = documentsDirectory.appendingPathComponent("merged_\(timestamp).m4a")
        
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