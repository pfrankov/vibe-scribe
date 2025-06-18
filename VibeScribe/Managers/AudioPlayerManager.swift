//
//  AudioPlayerManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import Foundation
import AVFoundation

// --- Audio Player Logic --- 
class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var player: AVAudioPlayer?
    
    private var timer: Timer?
    var wasPlayingBeforeScrub = false

    func setupPlayer(url: URL) {
        do {
            // Stop existing player/timer if any
            stopAndCleanup()
            
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            duration = player?.duration ?? 0.0
            currentTime = 0.0 // Reset time
            print("Audio player setup complete. Duration: \(duration)")
        } catch {
            print("Error setting up audio player: \(error.localizedDescription)")
            player = nil
            duration = 0.0
            currentTime = 0.0
        }
    }

    func togglePlayPause() {
        guard let player = player else { return }
        
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
        guard let player = player else { return }
        player.currentTime = max(0, min(time, duration)) // Clamp value
        self.currentTime = player.currentTime // Update published value immediately
        if !isPlaying && wasPlayingBeforeScrub {
             // If paused due to scrubbing, resume playback after seeking
             player.play()
             isPlaying = true
             startTimer()
             wasPlayingBeforeScrub = false // Reset flag
         }
    }
    
    // Call this when user starts dragging the slider
    func scrubbingStarted() {
         guard let player = player else { return }
         wasPlayingBeforeScrub = player.isPlaying
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
        currentTime = 0.0
        duration = 0.0
        wasPlayingBeforeScrub = false
        print("Player stopped and cleaned up")
    }

    private func startTimer() {
        stopTimer() // Ensure no duplicates
        
        // Use standard Timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func updateProgress() {
        guard let player = player else { return }
        // Only update if playing and time has actually changed
        if player.isPlaying && self.currentTime != player.currentTime {
            self.currentTime = player.currentTime
        }
    }
    
    // MARK: - AVAudioPlayerDelegate Methods
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("Playback finished. Success: \(flag)")
        // Ensure UI updates on main thread if delegate methods aren't guaranteed
        DispatchQueue.main.async {
            self.isPlaying = false
            self.stopTimer()
            // Reset progress to the beginning
            self.currentTime = 0.0
            player.currentTime = 0.0 // Ensure player time resets too
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(error?.localizedDescription ?? "Unknown error")")
        // Ensure UI updates on main thread
        DispatchQueue.main.async {
            self.isPlaying = false
            self.stopTimer()
            // Handle error appropriately - maybe show an alert
        }
    }
} 