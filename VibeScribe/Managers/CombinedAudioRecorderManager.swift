//
//  CombinedAudioRecorderManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 15.04.2025.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine

@MainActor
class CombinedAudioRecorderManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0.0
    @Published var error: Error? = nil
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10)
    @Published var isSystemAudioRecording = false // Indicates if system audio is being recorded
    
    private var micRecorderManager = AudioRecorderManager()
    private var systemRecorderManager = SystemAudioRecorderManager()
    private var systemAudioOutputURL: URL?
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe microphone recorder state
        micRecorderManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.isRecording = isRecording
            }
            .store(in: &cancellables)
        
        micRecorderManager.$recordingTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                self?.recordingTime = time
            }
            .store(in: &cancellables)
        
        micRecorderManager.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    self?.error = error
                }
            }
            .store(in: &cancellables)
        
        // Observe system recorder state
        systemRecorderManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.isSystemAudioRecording = isRecording
            }
            .store(in: &cancellables)
        
        systemRecorderManager.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if let error = error {
                    Logger.warning("System audio recording error (continuing with microphone only): \(error.localizedDescription)", category: .audio)
                    // Don't set main error - continue with microphone only
                }
            }
            .store(in: &cancellables)
        
        // Combine audio levels from both sources
        Publishers.CombineLatest(
            micRecorderManager.$audioLevels,
            systemRecorderManager.$audioLevels
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] micLevels, systemLevels in
            if self?.isSystemAudioRecording == true {
                // Combine levels by adding squared values (energy) and taking square root
                // This gives a more accurate representation of combined audio
                self?.audioLevels = zip(micLevels, systemLevels).map { mic, sys in
                    let combinedEnergy = mic * mic + sys * sys
                    return Float(sqrt(Double(combinedEnergy)))
                }
            } else {
                // Use only microphone levels
                self?.audioLevels = micLevels
            }
        }
        .store(in: &cancellables)
    }
    
    func startRecording() {
        Logger.info("Starting combined audio recording", category: .audio)
        error = nil
        
        // Always start microphone recording first
        micRecorderManager.startRecording()
        
        // Try to start system audio recording if available
        Task {
            if #available(macOS 12.3, *) {
                let hasPermission = await systemRecorderManager.hasScreenCapturePermission()
                
                if hasPermission {
                    Logger.info("System audio permission available - starting system audio recording", category: .audio)
                    
                    // Generate unique URL for system audio
                    let timestamp = Int(Date().timeIntervalSince1970)
                    let recordingsDir = getRecordingsDirectory()
                    let sysURL = recordingsDir.appendingPathComponent("sys_\(timestamp).caf")
                    
                    await MainActor.run {
                        self.systemAudioOutputURL = sysURL
                        self.systemRecorderManager.startRecording(outputURL: sysURL)
                    }
                } else {
                    Logger.info("System audio permission not available - recording microphone only", category: .audio)
                }
            } else {
                Logger.info("System audio recording not available on this macOS version - recording microphone only", category: .audio)
            }
        }
    }
    
    func stopRecording() -> (url: URL, duration: TimeInterval, includesSystemAudio: Bool)? {
        Logger.info("Stopping combined audio recording", category: .audio)
        
        // Stop microphone recording
        guard let micResult = micRecorderManager.stopRecording() else {
            Logger.error("Failed to stop microphone recording", category: .audio)
            return nil
        }
        
        var systemAudioURL: URL?
        let wasSystemAudioRecording = isSystemAudioRecording
        
        // Stop system audio recording if it was active
        if isSystemAudioRecording {
            systemRecorderManager.stopRecording()
            systemAudioURL = systemAudioOutputURL
            Logger.info("Stopped system audio recording", category: .audio)
        }
        
        // If we have both microphone and system audio, merge them
        if let sysURL = systemAudioURL, wasSystemAudioRecording {
            Logger.info("Merging microphone and system audio files", category: .audio)
            
            // Use a completion handler approach for merging
            let semaphore = DispatchSemaphore(value: 0)
            var mergedURL: URL?
            var mergeError: Error?
            
            AudioUtils.mergeAudioFiles(micURL: micResult.url, systemURL: sysURL) { result in
                switch result {
                case .success(let url):
                    mergedURL = url
                    Logger.info("Successfully merged audio files", category: .audio)
                case .failure(let error):
                    mergeError = error
                    Logger.error("Failed to merge audio files", error: error, category: .audio)
                }
                semaphore.signal()
            }
            
            // Wait for merge completion
            semaphore.wait()
            
            if let finalURL = mergedURL {
                // Clean up temporary files
                cleanupTemporaryFiles(urls: [micResult.url, sysURL])
                return (finalURL, micResult.duration, true)
            } else {
                // Merge failed, use microphone only
                if let error = mergeError {
                    Logger.error("Using microphone-only recording due to merge failure", error: error, category: .audio)
                }
                cleanupTemporaryFiles(urls: [sysURL]) // Clean up system audio file
                return (micResult.url, micResult.duration, false)
            }
        } else {
            // Only microphone recording
            Logger.info("Saving microphone-only recording", category: .audio)
            return (micResult.url, micResult.duration, false)
        }
    }
    
    func cancelRecording() {
        Logger.info("Cancelling combined audio recording", category: .audio)
        
        micRecorderManager.cancelRecording()
        
        if isSystemAudioRecording {
            systemRecorderManager.stopRecording()
            if let sysURL = systemAudioOutputURL {
                cleanupTemporaryFiles(urls: [sysURL])
            }
        }
        
        systemAudioOutputURL = nil
    }
    
    private func getRecordingsDirectory() -> URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupportURL = urls.first else {
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
            return documentsURL.appendingPathComponent(bundleID).appendingPathComponent("Recordings")
        }
        
        let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
        let recordingsURL = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("Recordings")

        if !fileManager.fileExists(atPath: recordingsURL.path) {
            do {
                try fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logger.error("Error creating recordings directory", error: error, category: .audio)
            }
        }
        return recordingsURL
    }
    
    private func cleanupTemporaryFiles(urls: [URL]) {
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
                Logger.info("Cleaned up temporary file: \(url.path)", category: .audio)
            } catch {
                Logger.warning("Could not delete temporary file \(url.path): \(error.localizedDescription)", category: .audio)
            }
        }
    }
} 