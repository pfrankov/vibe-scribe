//
//  AudioPlayerManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import Foundation
import AVFoundation
import QuartzCore
import Accelerate

/// Audio player manager backed by `AVAudioEngine` for high-quality rate changes.
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isReady = false
    @Published var playbackSpeed: Float = 1.0
    @Published var waveformSamples: [Float] = []
    @Published var playbackProgress: Double = 0

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    private var audioFile: AVAudioFile?
    private var audioLengthSamples: AVAudioFramePosition = 0
    private var sampleRate: Double = 44_100
    private var currentFrame: AVAudioFramePosition = 0

    private var timer: Timer?
    private var resumeAfterSeek = false

    private var rateAnimationTimer: Timer?
    private var rateAnimationStart: CFTimeInterval = 0
    private var rateAnimationSource: Float = 1.0
    private var rateAnimationTarget: Float = 1.0

    private let playbackSpeeds: [Float] = [1.5, 1.75, 2.0, 1.0]
    private let rateAnimationDuration: CFTimeInterval = 0.7
    private let targetWaveformSampleCount = 1200

    private var waveformGenerationID = UUID()

    override init() {
        super.init()
        engine.attach(playerNode)
        engine.attach(timePitch)
        timePitch.overlap = 8
    }

    // MARK: - Public API

    func setupPlayer(url: URL) {
        stopAndCleanup()

        do {
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            audioLengthSamples = file.length
            sampleRate = file.processingFormat.sampleRate
            duration = audioLengthSamples > 0 ? Double(audioLengthSamples) / sampleRate : 0
            currentTime = 0
            currentFrame = 0

            configureEngine(for: file.processingFormat)
            timePitch.rate = playbackSpeed

            try engine.start()
            isReady = true
            playbackProgress = 0

            waveformSamples = []
            let generationID = UUID()
            waveformGenerationID = generationID
            generateWaveformSamples(for: url,
                                    frameCount: audioLengthSamples,
                                    generationID: generationID)

            Logger.info("Audio player setup. Duration: \(duration)", category: .audio)
        } catch {
            Logger.error("Failed to setup audio engine player", error: error, category: .audio)
            resetState()
        }
    }

    func togglePlayPause() {
        guard isReady else { return }

        if isPlaying {
            pausePlayback(clearResumeFlag: true)
        } else {
            if currentFrame >= audioLengthSamples {
                currentFrame = 0
                currentTime = 0
            }
            startPlayback()
        }
    }

    func cyclePlaybackSpeed() {
        guard !playbackSpeeds.isEmpty else { return }
        let currentIndex = playbackSpeeds.firstIndex(of: playbackSpeed) ?? (playbackSpeeds.count - 1)
        let nextIndex = (currentIndex + 1) % playbackSpeeds.count
        setPlaybackSpeed(playbackSpeeds[nextIndex])
    }

    func seek(to time: TimeInterval) {
        guard isReady else { return }

        let clampedTime = max(0, min(time, duration))
        currentFrame = AVAudioFramePosition(clampedTime * sampleRate)
        currentTime = clampedTime
        if duration > 0 {
            let progress = clampedTime / duration
            playbackProgress = min(max(progress, 0), 1)
        } else {
            playbackProgress = 0
        }

        let shouldResume = resumeAfterSeek || isPlaying

        playerNode.stop()
        if resumeAfterSeek {
            resumeAfterSeek = false
        }

        if shouldResume {
            startPlayback()
        }
    }

    func scrubbingStarted() {
        resumeAfterSeek = isPlaying
        pausePlayback()
    }

    func previewScrubProgress(_ progress: Double) {
        guard isReady, duration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        playbackProgress = clamped
        currentTime = clamped * duration
    }

    func seek(toProgress progress: Double) {
        guard duration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let targetTime = clamped * duration
        seek(to: targetTime)
    }

    func skipForward(_ seconds: TimeInterval = 10) {
        guard isReady else { return }
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
        Logger.debug("Skipped forward \(seconds) seconds to \(newTime)", category: .audio)
    }
    
    func skipBackward(_ seconds: TimeInterval = 10) {
        guard isReady else { return }
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
        Logger.debug("Skipped backward \(seconds) seconds to \(newTime)", category: .audio)
    }

    func stopAndCleanup() {
        pausePlayback(clearResumeFlag: true)
        playerNode.stop()
        engine.stop()
        engine.reset()
        stopTimer()
        stopRateAnimation()
        waveformGenerationID = UUID()
        resetState()
        Logger.debug("Player stopped and cleaned up", category: .audio)
    }

    // MARK: - Internal Playback

    private func startPlayback() {
        guard let file = audioFile else { return }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Logger.error("Failed to start audio engine", error: error, category: .audio)
                return
            }
        }

        if currentFrame >= audioLengthSamples {
            currentFrame = 0
            currentTime = 0
        }

        let framesRemaining = audioLengthSamples - currentFrame
        guard framesRemaining > 0 else { return }

        let frameCount = AVAudioFrameCount(framesRemaining)
        playerNode.stop()
        scheduleSegment(file: file, startingFrame: currentFrame, frameCount: frameCount)
        playerNode.play()

        if audioLengthSamples > 0 {
            let progress = Double(currentFrame) / Double(audioLengthSamples)
            playbackProgress = min(max(progress, 0), 1)
        }

        isPlaying = true
        startTimer()
    }

    private func pausePlayback(clearResumeFlag: Bool = false) {
        guard isPlaying else { return }

        if let playedFrames = currentlyRenderedFrames() {
            currentFrame = min(audioLengthSamples, currentFrame + playedFrames)
            currentTime = Double(currentFrame) / sampleRate
        }

        playerNode.pause()
        isPlaying = false
        if clearResumeFlag {
            resumeAfterSeek = false
        }
        stopTimer()
    }

    private func scheduleSegment(file: AVAudioFile, startingFrame: AVAudioFramePosition, frameCount: AVAudioFrameCount) {
        playerNode.scheduleSegment(file, startingFrame: startingFrame, frameCount: frameCount, at: nil, completionHandler: nil)
    }

    private func configureEngine(for format: AVAudioFormat) {
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(playerNode, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    private func currentlyRenderedFrames() -> AVAudioFramePosition? {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        return AVAudioFramePosition(playerTime.sampleTime)
    }

    // MARK: - Timers

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let rendered = self.currentlyRenderedFrames() {
                let absoluteFrames = self.currentFrame + rendered
                if absoluteFrames >= self.audioLengthSamples {
                    self.currentFrame = self.audioLengthSamples
                    self.currentTime = self.duration
                    if self.audioLengthSamples > 0 {
                        self.playbackProgress = 1
                    }
                    self.isPlaying = false
                    self.stopTimer()
                } else {
                    let newTime = Double(absoluteFrames) / self.sampleRate
                    if newTime != self.currentTime {
                        self.currentTime = newTime
                    }
                    if self.audioLengthSamples > 0 {
                        let progress = Double(absoluteFrames) / Double(self.audioLengthSamples)
                        let clamped = min(max(progress, 0), 1)
                        if clamped != self.playbackProgress {
                            self.playbackProgress = clamped
                        }
                    }
                }
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Playback Speed

    private func setPlaybackSpeed(_ newValue: Float) {
        let clamped = max(0.5, min(newValue, 2.0))
        playbackSpeed = clamped
        animateRateChange(to: clamped)
    }

    private func animateRateChange(to target: Float) {
        stopRateAnimation()

        let currentRate = timePitch.rate
        if abs(currentRate - target) < 0.001 {
            timePitch.rate = target
            return
        }

        rateAnimationStart = CACurrentMediaTime()
        rateAnimationSource = currentRate
        rateAnimationTarget = target

        rateAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            let elapsed = CACurrentMediaTime() - self.rateAnimationStart
            let progress = min(1.0, elapsed / self.rateAnimationDuration)
            let eased = self.easeInOut(progress)
            let interpolated = self.rateAnimationSource + (self.rateAnimationTarget - self.rateAnimationSource) * Float(eased)
            self.timePitch.rate = interpolated

            if progress >= 1.0 {
                timer.invalidate()
                self.rateAnimationTimer = nil
                self.timePitch.rate = self.rateAnimationTarget
            }
        }

        if let rateAnimationTimer {
            RunLoop.main.add(rateAnimationTimer, forMode: .common)
        }
    }

    private func stopRateAnimation() {
        rateAnimationTimer?.invalidate()
        rateAnimationTimer = nil
    }

    private func easeInOut(_ t: Double) -> Double {
        // Smooth ease-in-out curve for gentle transitions
        return 0.5 - cos(.pi * t) / 2.0
    }

    // MARK: - Helpers

    private func resetState() {
        audioFile = nil
        audioLengthSamples = 0
        sampleRate = 44_100
        currentFrame = 0
        currentTime = 0
        duration = 0
        isPlaying = false
        isReady = false
        resumeAfterSeek = false
        waveformSamples = []
        playbackProgress = 0
    }
}

// MARK: - Waveform Generation

extension AudioPlayerManager {
    private func generateWaveformSamples(for url: URL,
                                         frameCount: AVAudioFramePosition,
                                         generationID: UUID) {
        guard frameCount > 0 else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.waveformGenerationID == generationID else { return }
                self.waveformSamples = []
            }
            return
        }

        let totalFrames = Int(frameCount)

        let sourceSampleRate = sampleRate
        let durationSeconds = sourceSampleRate > 0 ? Double(totalFrames) / sourceSampleRate : 0
        let dynamicTarget = min(16_000, max(targetWaveformSampleCount, Int(durationSeconds * 14)))
        let bucketCount = min(dynamicTarget, max(1, totalFrames))

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            // Fast path: downsample decode using AVAssetReader to ~4 kHz mono
            // AVAssetReader requires sample rate between 8 kHz and 192 kHz
            let targetSampleRate: Double = 8_000
            let asset = AVURLAsset(url: url)
            guard let track = asset.tracks(withMediaType: .audio).first else {
                Logger.warning("No audio track for waveform generation", category: .audio)
                return
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMIsNonInterleaved: false,
                AVSampleRateKey: targetSampleRate
            ]

            var composite: [Float] = Array(repeating: 0, count: bucketCount)
            var bucketSumSquares: [Double] = Array(repeating: 0, count: bucketCount)
            var bucketCounts: [Int] = Array(repeating: 0, count: bucketCount)

            do {
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
                output.alwaysCopiesSampleData = false
                if reader.canAdd(output) { reader.add(output) }
                if !reader.startReading() {
                    Logger.error("AVAssetReader failed to start", category: .audio)
                    return
                }

                let framesPerBucketDS = max(1, Int(ceil(targetSampleRate * durationSeconds / Double(bucketCount))))
                var processedFrames: Int = 0

                while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
                    guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
                    var lengthAtOffset = 0
                    var totalLength = 0
                    var dataPointer: UnsafeMutablePointer<Int8>?
                    let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
                    if status != kCMBlockBufferNoErr || dataPointer == nil || totalLength <= 0 {
                        continue
                    }
                    let count = totalLength / MemoryLayout<Float>.size
                    let floatPtr = dataPointer!.withMemoryRebound(to: Float.self, capacity: count) { $0 }

                    var i = 0
                    while i < count {
                        let framesIntoBucket = processedFrames % framesPerBucketDS
                        let framesRemainingInBucket = framesPerBucketDS - framesIntoBucket
                        let chunkLen = min(framesRemainingInBucket, count - i)

                        var maxVal: Float = 0
                        var sumSq: Float = 0
                        vDSP_maxv(floatPtr.advanced(by: i), 1, &maxVal, vDSP_Length(chunkLen))
                        vDSP_svesq(floatPtr.advanced(by: i), 1, &sumSq, vDSP_Length(chunkLen))

                        let bIdx = min(bucketCount - 1, processedFrames / framesPerBucketDS)
                        if maxVal > composite[bIdx] { composite[bIdx] = maxVal }
                        bucketSumSquares[bIdx] += Double(sumSq)
                        bucketCounts[bIdx] += chunkLen

                        processedFrames += chunkLen
                        i += chunkLen
                    }
                    CMSampleBufferInvalidate(sampleBuffer)
                }

                if reader.status == .failed {
                    Logger.error("AVAssetReader failed during reading: \(reader.error?.localizedDescription ?? "unknown")", category: .audio)
                }

                if composite.isEmpty {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.waveformGenerationID == generationID else { return }
                        self.waveformSamples = []
                    }
                    return
                }

                // Map to dB to preserve contrast across long ranges
                @inline(__always) func ampToDb(_ v: Float) -> Float {
                    return 20 * log10(max(v, 1e-6))
                }
                var dbValues = composite.map { ampToDb($0) }

                // Robust normalization on dB values
                func percentileDb(_ data: [Float], _ p: Double) -> Float {
                    let n = data.count
                    if n == 0 { return -60 }
                    let sorted = data.sorted()
                    let pos = min(max(p, 0), 1) * Double(n - 1)
                    let lower = Int(floor(pos))
                    let upper = Int(ceil(pos))
                    if lower == upper { return sorted[lower] }
                    let t = Float(pos - Double(lower))
                    return sorted[lower] * (1 - t) + sorted[upper] * t
                }

                let hi = percentileDb(dbValues, 0.999)
                let loCandidate = percentileDb(dbValues, 0.10)
                let dynamicRange: Float = 48 // dB
                let lo = max(hi - dynamicRange, loCandidate)
                let span = max(6, hi - lo) // min range

                var normalized = dbValues.map { v -> Float in
                    let x = (v - lo) / span
                    return max(0, min(1, x))
                }

                // Subtle neighbor smoothing
                if normalized.count > 2 {
                    var out = normalized
                    for i in 0..<normalized.count {
                        let l = i > 0 ? normalized[i - 1] : normalized[i]
                        let c = normalized[i]
                        let r = i + 1 < normalized.count ? normalized[i + 1] : normalized[i]
                        out[i] = c * 0.7 + (l + r) * 0.15
                    }
                    normalized = out
                }

                // Gentle gamma to lift quieter parts slightly (editor-like look)
                let bucketDurationSeconds = durationSeconds / Double(bucketCount)
                let clampedDuration = min(max(bucketDurationSeconds, 0), 0.4)
                let t = max(0.0, min(1.0, clampedDuration / 0.4))
                let gamma = Float(0.9 + 0.15 * t) // 0.9…1.05
                var shaped = normalized.map { pow($0, gamma) }

                let floorValue = max(0.0015, 0.006 - Float(t) * 0.003)
                let finalWave = shaped.map { max(floorValue, min(1.0, $0)) }

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.waveformGenerationID == generationID else { return }
                    self.waveformSamples = finalWave
                }
            } catch {
                Logger.error("Waveform generation failed", error: error, category: .audio)
            }
        }

        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }
}
