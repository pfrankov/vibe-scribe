//
//  AudioPlayerManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import Foundation
import AVFoundation

/// Simple audio player manager with minimal surface area.
/// Behavior preserved; internal logs unified via Logger.
class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var player: AVAudioPlayer?
    
    private var timer: Timer?
    private var resumeAfterSeek = false

    // MARK: - Public API

    func setupPlayer(url: URL) {
        stopAndCleanup()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            self.duration = player.duration
            self.currentTime = 0
            Logger.info("Audio player setup. Duration: \(duration)", category: .audio)
        } catch {
            Logger.error("Failed to setup audio player", error: error, category: .audio)
            self.player = nil
            self.duration = 0
            self.currentTime = 0
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, duration))
        currentTime = player.currentTime
        if !isPlaying && resumeAfterSeek {
            player.play()
            isPlaying = true
            startTimer()
            resumeAfterSeek = false
        }
    }

    // Call when user starts dragging the slider
    func scrubbingStarted() {
        guard let player else { return }
        resumeAfterSeek = player.isPlaying
        if isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
        }
    }

    func stopAndCleanup() {
        player?.stop()
        stopTimer()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        resumeAfterSeek = false
        Logger.debug("Player stopped and cleaned up", category: .audio)
    }

    // MARK: - Internal

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, player.isPlaying else { return }
            let newTime = player.currentTime
            if newTime != self.currentTime {
                self.currentTime = newTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Logger.debug("Playback finished. Success: \(flag)", category: .audio)
        DispatchQueue.main.async {
            self.isPlaying = false
            self.stopTimer()
            self.currentTime = 0
            player.currentTime = 0
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Logger.error("Audio player decode error", error: error, category: .audio)
        DispatchQueue.main.async {
            self.isPlaying = false
            self.stopTimer()
        }
    }
}