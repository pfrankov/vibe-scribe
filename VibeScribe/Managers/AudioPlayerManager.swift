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
    private let waveformCache = WaveformCache.shared

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
    private var waveformTask: Task<Void, Never>?

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

            if let cachedSamples = waveformCache.cachedWaveform(for: url) {
                waveformGenerationID = UUID()
                waveformSamples = cachedSamples
                Logger.debug("Loaded cached waveform with \(cachedSamples.count) samples", category: .audio)
            } else {
                let generationID = UUID()
                waveformGenerationID = generationID
                generateWaveformSamples(for: url,
                                        frameCount: audioLengthSamples,
                                        generationID: generationID)
            }

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

    private func cancelWaveformGeneration() {
        waveformTask?.cancel()
        waveformTask = nil
    }

    private func resetState() {
        cancelWaveformGeneration()
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
        cancelWaveformGeneration()

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
        let asset = AVURLAsset(url: url)

        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                try Task.checkCancellation()

                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard let track = tracks.first else {
                    Logger.warning("No audio track for waveform generation", category: .audio)
                    await self.clearWaveformIfMatches(generationID)
                    return
                }

                try Task.checkCancellation()

                let buckets = try self.makeWaveformBuckets(asset: asset,
                                                           track: track,
                                                           bucketCount: bucketCount,
                                                           durationSeconds: durationSeconds)

                try Task.checkCancellation()

                guard !buckets.isEmpty else {
                    await self.clearWaveformIfMatches(generationID)
                    return
                }

                let normalized = self.normalizeWaveform(buckets,
                                                        durationSeconds: durationSeconds,
                                                        bucketCount: bucketCount)

                try Task.checkCancellation()

                let applied = await self.applyWaveformIfCurrent(normalized, generationID: generationID)
                if applied {
                    self.waveformCache.storeWaveform(normalized, for: url, duration: durationSeconds)
                    Logger.debug("Stored waveform cache with \(normalized.count) samples", category: .audio)
                }
            } catch is CancellationError {
                Logger.debug("Waveform generation cancelled", category: .audio)
            } catch {
                Logger.error("Waveform generation failed", error: error, category: .audio)
                await self.clearWaveformIfMatches(generationID)
            }
        }

        waveformTask = task
    }

    private func makeWaveformBuckets(asset: AVURLAsset,
                                     track: AVAssetTrack,
                                     bucketCount: Int,
                                     durationSeconds: Double) throws -> [Float] {
        let targetSampleRate: Double = 8_000
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: targetSampleRate
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw WaveformGenerationError.readerStartFailure(underlying: nil)
        }
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformGenerationError.readerStartFailure(underlying: reader.error)
        }

        let framesPerBucket = max(1, Int(ceil(targetSampleRate * durationSeconds / Double(bucketCount))))
        var buckets = [Float](repeating: 0, count: bucketCount)
        var processedFrames = 0

        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sampleBuffer) }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            var lengthAtOffset = 0
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )

            guard status == kCMBlockBufferNoErr,
                  let pointer = dataPointer,
                  totalLength > 0 else {
                continue
            }

            let frameCount = totalLength / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: frameCount) { basePointer in
                var index = 0
                while index < frameCount {
                    let framesIntoBucket = processedFrames % framesPerBucket
                    let framesRemainingInBucket = framesPerBucket - framesIntoBucket
                    let chunkLength = min(framesRemainingInBucket, frameCount - index)

                    var maxValue: Float = 0
                    vDSP_maxv(basePointer.advanced(by: index), 1, &maxValue, vDSP_Length(chunkLength))

                    let bucketIndex = min(bucketCount - 1, processedFrames / framesPerBucket)
                    if maxValue > buckets[bucketIndex] {
                        buckets[bucketIndex] = maxValue
                    }

                    processedFrames += chunkLength
                    index += chunkLength
                }
            }
        }

        if reader.status == .failed {
            throw WaveformGenerationError.readerFailure(underlying: reader.error)
        }

        return buckets
    }

    private func normalizeWaveform(_ buckets: [Float],
                                   durationSeconds: Double,
                                   bucketCount: Int) -> [Float] {
        guard !buckets.isEmpty else { return [] }

        let dbValues = buckets.map(Self.amplitudeToDecibels)
        let sorted = dbValues.sorted()

        let highPercentile = Self.percentile(in: sorted, percentile: 0.999)
        let lowCandidate = Self.percentile(in: sorted, percentile: 0.10)
        let dynamicRange: Float = 48
        let low = max(highPercentile - dynamicRange, lowCandidate)
        let span = max(6, highPercentile - low)

        var normalized = dbValues.map { value -> Float in
            let scaled = (value - low) / span
            return max(0, min(1, scaled))
        }

        if normalized.count > 2 {
            var smoothed = normalized
            for index in normalized.indices {
                let left = index > normalized.startIndex ? normalized[index - 1] : normalized[index]
                let center = normalized[index]
                let right = index + 1 < normalized.endIndex ? normalized[index + 1] : normalized[index]
                smoothed[index] = center * 0.7 + (left + right) * 0.15
            }
            normalized = smoothed
        }

        let bucketDuration = durationSeconds / Double(max(bucketCount, 1))
        let clampedDuration = min(max(bucketDuration, 0), 0.4)
        let t = max(0.0, min(1.0, clampedDuration / 0.4))
        let gamma = Float(0.9 + 0.15 * t)
        let floorValue = max(0.0015, 0.006 - Float(t) * 0.003)

        for index in normalized.indices {
            let shaped = pow(normalized[index], gamma)
            normalized[index] = max(floorValue, min(1.0, shaped))
        }

        return normalized
    }

    @MainActor
    private func applyWaveformIfCurrent(_ samples: [Float], generationID: UUID) -> Bool {
        guard waveformGenerationID == generationID else { return false }
        waveformSamples = samples
        return true
    }

    @MainActor
    private func clearWaveformIfMatches(_ generationID: UUID) {
        guard waveformGenerationID == generationID else { return }
        waveformSamples = []
    }

    private static func amplitudeToDecibels(_ value: Float) -> Float {
        20 * log10(max(value, 1e-6))
    }

    private static func percentile(in sortedData: [Float], percentile: Double) -> Float {
        guard !sortedData.isEmpty else { return -60 }
        let clamped = min(max(percentile, 0), 1)
        let position = clamped * Double(sortedData.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sortedData[lower] }
        let t = Float(position - Double(lower))
        return sortedData[lower] * (1 - t) + sortedData[upper] * t
    }

    private enum WaveformGenerationError: LocalizedError {
        case readerStartFailure(underlying: Error?)
        case readerFailure(underlying: Error?)

        var errorDescription: String? {
            switch self {
            case let .readerStartFailure(underlying):
                return "AVAssetReader failed to start: \(underlying?.localizedDescription ?? "unknown error")"
            case let .readerFailure(underlying):
                return "AVAssetReader failed during reading: \(underlying?.localizedDescription ?? "unknown error")"
            }
        }
    }
}
