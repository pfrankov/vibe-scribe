//
//  AudioUtils.swift
//  VibeScribe
//
//  Created by Gemini on \(Date()).
//

import Foundation
import AVFoundation

struct AudioUtils {
    
    // Merges two audio files into one, overlaying them.
    // Completion handler returns the URL of the merged file or an error.
    static func mergeAudioFiles(micURL: URL, systemURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        
        let composition = AVMutableComposition()
        
        // Create assets from URLs
        let micAsset = AVURLAsset(url: micURL)
        let systemAsset = AVURLAsset(url: systemURL)
        
        // Load tracks asynchronously (best practice)
        Task {
            do {
                // Load tracks for both assets
                guard let micAudioTrack = try await micAsset.loadTracks(withMediaType: .audio).first,
                      let systemAudioTrack = try await systemAsset.loadTracks(withMediaType: .audio).first else {
                    throw NSError(domain: "AudioUtils", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load audio tracks from one or both assets."])
                }
                
                // Create composition tracks
                guard let compositionMicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                      let compositionSystemTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                    throw NSError(domain: "AudioUtils", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create composition tracks."])
                }
                
                // Determine the duration (use the longer of the two)
                 let micDuration = try await micAsset.load(.duration)
                 let systemDuration = try await systemAsset.load(.duration)
                 let maxDuration = CMTimeMaximum(micDuration, systemDuration)
                 let timeRange = CMTimeRange(start: .zero, duration: maxDuration)
                
                // Insert audio tracks into composition
                try compositionMicTrack.insertTimeRange(timeRange, of: micAudioTrack, at: .zero)
                try compositionSystemTrack.insertTimeRange(timeRange, of: systemAudioTrack, at: .zero)
                
                // --- Export Session --- 
                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
                    throw NSError(domain: "AudioUtils", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create export session."])
                }
                
                // Generate unique output URL for merged file
                let timestamp = Int(Date().timeIntervalSince1970)
                guard let outputURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("merged_\(timestamp).m4a") else {
                     throw NSError(domain: "AudioUtils", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not create output URL for merged file."])
                }
                
                // Configure export session
                exportSession.outputURL = outputURL
                exportSession.outputFileType = .m4a
                
                // Perform the export asynchronously
                await exportSession.export()
                    
                // Check export status
                switch exportSession.status {
                case .completed:
                    print("Audio merge completed successfully: \(outputURL.path)")
                    completion(.success(outputURL))
                case .failed:
                    let error = exportSession.error ?? NSError(domain: "AudioUtils", code: 5, userInfo: [NSLocalizedDescriptionKey: "Export session failed with unknown error."])
                     print("Audio merge failed: \(error.localizedDescription)")
                    completion(.failure(error))
                case .cancelled:
                     print("Audio merge cancelled.")
                    completion(.failure(NSError(domain: "AudioUtils", code: 6, userInfo: [NSLocalizedDescriptionKey: "Export session cancelled."])))
                default:
                    completion(.failure(NSError(domain: "AudioUtils", code: 7, userInfo: [NSLocalizedDescriptionKey: "Export session ended with unexpected status: \(exportSession.status)"])))
                }
                
            } catch {
                print("Error during audio merging process: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
} 