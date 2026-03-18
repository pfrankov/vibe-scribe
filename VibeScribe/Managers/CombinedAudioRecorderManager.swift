//
//  CombinedAudioRecorderManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 15.04.2025.
//

import Foundation
import AVFoundation
import Combine

@MainActor
class CombinedAudioRecorderManager: NSObject, ObservableObject {
    // Represents an active session (recording or paused)
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0.0
    @Published var error: Error? = nil
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10)
    @Published var isSystemAudioRecording = false // Internal write state
    @Published var isSystemAudioEnabled = false   // UI source indicator
    
    private var micRecorderManager = AudioRecorderManager()
    private var systemRecorderManager = SystemAudioRecorderManager()
    private var systemAudioOutputURL: URL?
    private var cancellables = Set<AnyCancellable>()
    private var mockTimer: Timer?
    private var mockSessionStartAt: Date?
    private var mockAccumulatedDuration: TimeInterval = 0

    // Display smoothing (fast attack, slower release). No auto-gain — full scale preserved.
    private let smoothAttack: Float = 0.55
    private let smoothRelease: Float = 0.20
    
    override init() {
        super.init()
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe microphone time and errors (session state is managed here)
        
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
            .sink { error in
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
            guard let self else { return }
            let combined: [Float]
            if self.isSystemAudioRecording {
                // Energy sum to combine sources consistently
                combined = zip(micLevels, systemLevels).map { mic, sys in
                    let energy = mic * mic + sys * sys
                    return Float(sqrt(Double(energy)))
                }
            } else {
                combined = micLevels
            }

            // Preserve full scale (0..1). Apply only smoothing for visual stability.
            let unclipped = combined.map { min(1.0, max(0.0, $0)) }
            var smoothed: [Float] = Array(repeating: 0, count: unclipped.count)
            for i in 0..<unclipped.count {
                let prev = (i < self.audioLevels.count) ? self.audioLevels[i] : 0
                let next = unclipped[i]
                let alpha = next > prev ? self.smoothAttack : self.smoothRelease
                smoothed[i] = prev + alpha * (next - prev)
            }
            self.audioLevels = smoothed
        }
        .store(in: &cancellables)
    }
    
    func startRecording() {
        if UITestMockPipeline.isEnabled {
            startMockRecording()
            return
        }

        Logger.info("Starting combined audio recording", category: .audio)
        error = nil
        isPaused = false

        // Always start microphone recording first
        micRecorderManager.startRecording()
        
        Task {
            let hasPermission = await systemRecorderManager.hasScreenCapturePermission()
            if hasPermission {
                Logger.info("System audio permission available - starting system audio recording", category: .audio)
                self.isSystemAudioEnabled = true
                let timestamp = Int(Date().timeIntervalSince1970)
                let recordingsDir: URL
                if let dir = try? AudioUtils.getRecordingsDirectory() {
                    recordingsDir = dir
                } else {
                    let fm = FileManager.default
                    let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
                    let tempDir = fm.temporaryDirectory
                        .appendingPathComponent(bundleID, isDirectory: true)
                        .appendingPathComponent("Recordings", isDirectory: true)
                    if !fm.fileExists(atPath: tempDir.path) {
                        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                    }
                    recordingsDir = tempDir
                }
                let sysURL = recordingsDir.appendingPathComponent("sys_\(timestamp).caf")
                await MainActor.run {
                    self.systemAudioOutputURL = sysURL
                    self.systemRecorderManager.startRecording(outputURL: sysURL)
                }
            } else {
                Logger.info("System audio permission not available - recording microphone only", category: .audio)
                self.isSystemAudioEnabled = false
            }
        }
        isRecording = true
    }
    
    func stopRecording() -> (url: URL, duration: TimeInterval, includesSystemAudio: Bool)? {
        if UITestMockPipeline.isEnabled {
            return stopMockRecording()
        }

        Logger.info("Stopping combined audio recording", category: .audio)
        
        // Stop microphone recording (works from active or paused states)
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
                isRecording = false
                isPaused = false
                return (finalURL, micResult.duration, true)
            } else {
                // Merge failed, use microphone only
                if let error = mergeError {
                    Logger.error("Using microphone-only recording due to merge failure", error: error, category: .audio)
                }
                cleanupTemporaryFiles(urls: [sysURL]) // Clean up system audio file
                isRecording = false
                isPaused = false
                return (micResult.url, micResult.duration, false)
            }
        } else {
            // Only microphone recording
            Logger.info("Saving microphone-only recording", category: .audio)
            isRecording = false
            isPaused = false
            return (micResult.url, micResult.duration, false)
        }
    }
    
    func cancelRecording() {
        if UITestMockPipeline.isEnabled {
            cancelMockRecording()
            return
        }

        Logger.info("Cancelling combined audio recording", category: .audio)
        
        micRecorderManager.cancelRecording()
        
        if isSystemAudioRecording {
            systemRecorderManager.stopRecording()
            if let sysURL = systemAudioOutputURL {
                cleanupTemporaryFiles(urls: [sysURL])
            }
        }
        
        systemAudioOutputURL = nil
        isPaused = false
        isRecording = false
    }

    func pauseRecording() {
        if UITestMockPipeline.isEnabled {
            pauseMockRecording()
            return
        }

        guard isRecording, !isPaused else { return }
        micRecorderManager.pauseRecording()
        systemRecorderManager.pauseRecording()
        isPaused = true
    }

    func resumeRecording() {
        if UITestMockPipeline.isEnabled {
            resumeMockRecording()
            return
        }

        guard isRecording, isPaused else { return }
        micRecorderManager.resumeRecording()
        systemRecorderManager.resumeRecording()
        isPaused = false
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

    // MARK: - UI Test Mock Recording

    private func startMockRecording() {
        error = nil
        isRecording = true
        isPaused = false
        isSystemAudioRecording = false
        isSystemAudioEnabled = false
        recordingTime = 0
        mockAccumulatedDuration = 0
        mockSessionStartAt = Date()
        startMockTimerIfNeeded()
        Logger.info("Started mock recording session for UI tests", category: .audio)
    }

    private func stopMockRecording() -> (url: URL, duration: TimeInterval, includesSystemAudio: Bool)? {
        guard isRecording else { return nil }

        commitActiveMockSegmentIfNeeded()
        recordingTime = mockAccumulatedDuration
        stopMockTimer()

        do {
            let mockURL = try UITestMockPipeline.makeMockRecordingCopyURL()
            let duration = max(recordingTime, UITestMockPipeline.minimumRecordingDuration)
            isRecording = false
            isPaused = false
            mockSessionStartAt = nil
            mockAccumulatedDuration = 0
            Logger.info("Saved mock recording file for UI tests: \(mockURL.lastPathComponent)", category: .audio)
            return (mockURL, duration, false)
        } catch {
            self.error = error
            Logger.error("Failed to create mock recording file", error: error, category: .audio)
            isRecording = false
            isPaused = false
            mockSessionStartAt = nil
            mockAccumulatedDuration = 0
            return nil
        }
    }

    private func cancelMockRecording() {
        stopMockTimer()
        mockSessionStartAt = nil
        mockAccumulatedDuration = 0
        recordingTime = 0
        isPaused = false
        isRecording = false
        audioLevels = Array(repeating: 0, count: 10)
        Logger.info("Cancelled mock recording session for UI tests", category: .audio)
    }

    private func pauseMockRecording() {
        guard isRecording, !isPaused else { return }
        commitActiveMockSegmentIfNeeded()
        recordingTime = mockAccumulatedDuration
        isPaused = true
    }

    private func resumeMockRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        mockSessionStartAt = Date()
    }

    private func startMockTimerIfNeeded() {
        stopMockTimer()
        mockTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(handleMockTimerTick),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopMockTimer() {
        mockTimer?.invalidate()
        mockTimer = nil
    }

    private func syncMockDuration() {
        guard isRecording else { return }
        if let startedAt = mockSessionStartAt, !isPaused {
            recordingTime = mockAccumulatedDuration + Date().timeIntervalSince(startedAt)
        } else {
            recordingTime = mockAccumulatedDuration
        }
    }

    private func updateMockRecordingTime() {
        syncMockDuration()
    }

    private func commitActiveMockSegmentIfNeeded() {
        guard let startedAt = mockSessionStartAt else { return }
        mockAccumulatedDuration += Date().timeIntervalSince(startedAt)
        mockSessionStartAt = nil
    }

    @objc
    private func handleMockTimerTick() {
        guard isRecording else { return }
        updateMockRecordingTime()

        // Keep waveform slightly animated for the overlay during tests.
        if isPaused {
            audioLevels = Array(repeating: 0.05, count: 10)
        } else {
            let wave = (0..<10).map { index -> Float in
                let phase = Float(recordingTime * 2.5 + Double(index) * 0.6)
                return max(0.06, min(0.95, (sin(phase) + 1.15) / 2.3))
            }
            audioLevels = wave
        }
    }
}
