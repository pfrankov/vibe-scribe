//
//  AudioPlayerManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import Foundation
import AVFoundation
import QuartzCore

/// Audio player manager backed by `AVAudioEngine` for high-quality rate changes.
final class AudioPlayerManager: NSObject, ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isReady = false
    @Published var playbackSpeed: Float = 1.0

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

    func stopAndCleanup() {
        pausePlayback(clearResumeFlag: true)
        playerNode.stop()
        engine.stop()
        engine.reset()
        stopTimer()
        stopRateAnimation()
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
                    self.currentTime = self.duration
                    self.isPlaying = false
                    self.stopTimer()
                } else {
                    let newTime = Double(absoluteFrames) / self.sampleRate
                    if newTime != self.currentTime {
                        self.currentTime = newTime
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
    }
}
