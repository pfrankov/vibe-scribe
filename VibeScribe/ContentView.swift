//
//  ContentView.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI
import AVFoundation // Import AVFoundation

// --- Audio Player Logic --- 

class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var player: AVAudioPlayer?
    
    private var timer: Timer?
    private var displayLink: CADisplayLink? // Alternative timer for smoother UI updates
    var wasPlayingBeforeScrub = false

    func setupPlayer(url: URL) {
        do {
            // Stop existing player/timer if any
            stopAndCleanup()
            
            // AVAudioSession configuration removed (not available/needed on macOS for basic playback)
            // try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            // try AVAudioSession.sharedInstance().setActive(true)
            
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
        // Deactivate audio session if needed (removed as unavailable)
        // try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("Player stopped and cleaned up")
    }

    private func startTimer() {
        stopTimer() // Ensure no duplicates
        // Use CADisplayLink for smoother UI updates tied to screen refresh rate (Removed - unavailable)
        // displayLink = CADisplayLink(target: self, selector: #selector(updateProgress))
        // displayLink?.add(to: .current, forMode: .common)
        
        // Use standard Timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func stopTimer() {
        // displayLink?.invalidate()
        // displayLink = nil
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
        isPlaying = false
        stopTimer()
        // Reset progress to the beginning
        self.currentTime = 0.0
        player.currentTime = 0.0
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(error?.localizedDescription ?? "Unknown error")")
        isPlaying = false
        stopTimer()
        // Handle error appropriately
    }
}

// Define a simple structure for a record
struct Record: Identifiable, Hashable {
    let id = UUID()
    let name: String
    // Add sample date and duration for UI display (can be replaced with real data later)
    let date: Date = Date()
    let duration: TimeInterval = Double.random(in: 30...300) // Random duration between 30s and 5m
    let hasTranscription: Bool = Bool.random() // Randomly decide if transcription is ready
}

// Helper to format duration
func formatDuration(_ duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: duration) ?? "0s"
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedRecord: Record? = nil // State to manage which detail view to show

    // Sample data for the list
    @State private var records = [
        Record(name: "Meeting Notes 2024-04-21"),
        Record(name: "Idea Brainstorm"),
        Record(name: "Lecture Recording"),
        Record(name: "Quick Memo"),
        Record(name: "Project Update")
    ]

    var body: some View {
        // Main container with adjusted spacing
        VStack(spacing: 0) { // Remove default VStack spacing, manage manually

            // Custom Tab Bar Area
            HStack(spacing: 0) { // No spacing between buttons
                TabBarButton(title: "Records", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabBarButton(title: "Settings", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
            }
            .padding(.horizontal) // Padding for the whole tab bar
            .padding(.top, 10)    // Padding above the tab bar
            .padding(.bottom, 5) // Space between tabs and divider

            Divider()
                .padding(.horizontal) // Keep divider padding

            // Content Area with Animation
            ZStack { // Use ZStack for smooth transitions
                if selectedTab == 0 {
                    RecordsListView(records: records, selectedRecord: $selectedRecord)
                        .transition(.opacity) // Fade transition
                } else {
                    SettingsView()
                        .transition(.opacity) // Fade transition
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab) // Apply animation to content switching
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure content fills space

            // Footer Area
            VStack(spacing: 0) { // Use VStack for Divider + Button row
                Divider()
                    .padding(.horizontal) // Match top divider padding

                // Quit button row
                HStack {
                    Spacer() // Push button to the right
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    // Add specific padding for the button if needed, or rely on HStack padding
                    // .padding(.trailing)
                }
                .padding(.vertical, 10) // Padding for the quit button row
                .padding(.horizontal)    // Horizontal padding for the row
                .background(Color(NSColor.windowBackgroundColor)) // Ensure background matches window
            }
            // Ensure Footer doesn't absorb extra space meant for content
            .layoutPriority(0) // Lower priority than the content ZStack
        }
        // Using .sheet to present the detail view modally
        .sheet(item: $selectedRecord) { record in
            RecordDetailView(record: record)
                // Set a minimum frame for the sheet
                .frame(minWidth: 400, minHeight: 450)
        }
    }
}

// --- Helper View for Tab Bar Button ---
struct TabBarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular) // Highlight selected
                .frame(maxWidth: .infinity) // Make button take available width
                .padding(.vertical, 8) // Vertical padding inside button
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear) // Subtle background for selected
                .contentShape(Rectangle()) // Ensure whole area is tappable
        }
        .buttonStyle(PlainButtonStyle()) // Remove default button chrome
        .foregroundColor(isSelected ? .accentColor : .primary) // Text color change
        .cornerRadius(6) // Slightly rounded corners for the background
        .animation(.easeInOut(duration: 0.15), value: isSelected) // Animate selection change
    }
}

// Separate view for the list of records
struct RecordsListView: View {
    let records: [Record]
    @Binding var selectedRecord: Record? // Binding to control the sheet presentation

    var body: some View {
        // Use a Group to switch between List and Empty State
        Group {
            if records.isEmpty {
                VStack {
                    Spacer() // Pushes content to center
                    Image(systemName: "list.bullet.clipboard")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 5)
                    Text("No recordings yet.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Your recordings will appear here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer() // Pushes content to center
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure VStack fills space
            } else {
                List {
                    ForEach(records) { record in
                        RecordRow(record: record)
                            .contentShape(Rectangle()) // Make the whole row tappable
                            .onTapGesture {
                                selectedRecord = record // Set the selected record to show the sheet
                            }
                    }
                }
                .listStyle(InsetListStyle()) // A slightly more modern list style
                // Removed top padding here, handled by Picker container now
            }
        }
    }
}

// View for a single row in the records list
struct RecordRow: View {
    let record: Record

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { // Added spacing for clarity
                Text(record.name).font(.headline)
                HStack {
                    Text(record.date, style: .date)
                    Text("-")
                    Text(formatDuration(record.duration))
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            Spacer()
            if record.hasTranscription {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.accentColor) // Use accent color for more style
                    .imageScale(.large) // Slightly larger icon
                    .help("Transcription available")
            } else {
                Image(systemName: "text.bubble")
                    .foregroundColor(.secondary) // Use secondary color
                    .imageScale(.large) // Slightly larger icon
                    .help("Transcription pending")
            }
        }
        .padding(.vertical, 8) // Increased vertical padding
    }
}

// Separate view for Settings
struct SettingsView: View {
    var body: some View {
        VStack(spacing: 15) { // Added spacing
            Spacer() // Push content to center
            Image(systemName: "gear.circle") // Placeholder Icon
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("Settings")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Application settings will be available here.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer() // Push content to center
        }
        .padding() // Add padding to the content
        // Ensure SettingsView fills the space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Detail view for a single record - Refactored to use AudioPlayerManager
struct RecordDetailView: View {
    let record: Record
    @Environment(\.dismiss) var dismiss
    @StateObject private var playerManager = AudioPlayerManager()
    @State private var currentSliderValue: Double = 0.0 // Separate state for live slider value

    // Computed property for transcription text for easier access
    private var transcriptionText: String {
        record.hasTranscription ? "This is the placeholder for the transcription text. It would appear here once the audio is processed...\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua." : "Transcription not available yet."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with Title and Close button
            HStack {
                Text(record.name).font(.title2).bold() // Make title bolder
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle()) // Remove button chrome
            }
            // .padding(.bottom) // Use spacing from VStack
            
            // --- Audio Player UI --- 
            VStack {
                HStack {
                    // Play/Pause Button
                    Button {
                        playerManager.togglePlayPause()
                    } label: {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 30)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Progress Slider
                    Slider(value: $currentSliderValue, in: 0...(playerManager.duration > 0 ? playerManager.duration : 1.0)) { editing in // Use currentSliderValue for live binding
                        if editing {
                            playerManager.scrubbingStarted()
                        } else {
                            playerManager.seek(to: currentSliderValue)
                        }
                    }
                    // Use the newer onChange signature
                    .onChange(of: playerManager.currentTime) { oldValue, newValue in // Updated signature
                         // Update slider position when player time changes externally (not during scrubbing)
                         if !playerManager.isPlaying && !playerManager.wasPlayingBeforeScrub { // A bit simplified logic, might need refinement
                             currentSliderValue = newValue // Use newValue here
                         }
                     }

                    
                    // Time Label
                    Text("\(formatTime(currentSliderValue)) / \(formatTime(playerManager.duration))") // Display slider time / total duration
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
            .disabled(playerManager.player == nil) // Disable based on manager state
            
            Divider()
            
            // Transcription Header with Copy Button
            HStack {
                Text("Transcription") // Removed colon for cleaner look
                    .font(.headline)
                Spacer()
                Button {
                    copyTranscription()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy Transcription")
                .buttonStyle(PlainButtonStyle())
                // Disable button if no transcription
                .disabled(!record.hasTranscription)
            }
            
            // Revert back to Text for performance and no blinking cursor
            // Keep ScrollView for potentially long transcriptions
            ScrollView {
                Text(transcriptionText)
                    .foregroundColor(record.hasTranscription ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // Ensure text aligns left
                    // Enable text selection
                    .textSelection(.enabled)
                    // Explicitly change cursor on hover
                    .onHover { hovering in
                        if hovering {
                            NSCursor.iBeam.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    // Add padding within the ScrollView for the Text
                    .padding(5)
            }
            .frame(maxHeight: .infinity) // Allow scroll view to expand
            // Removed background, cornerRadius, and border from TextEditor/ScrollView

            // --- Transcribe Button (Always visible) --- 
            Button {
                // Action to start transcription (placeholder)
                print("Start transcription for \(record.name)")
                // In a real app, you'd trigger the transcription process here
                // and update the record's state eventually.
            } label: {
                Label("Transcribe", systemImage: "sparkles")
            }
            .buttonStyle(.bordered) // Apply standard bordered style
            .frame(maxWidth: .infinity, alignment: .center) // Center the button
            .padding(.top, 5) // Add some space above the button
            
            // No need for Spacer() if ScrollView uses maxHeight: .infinity
        }
        .padding() // Overall padding for the sheet content
        .onAppear {
            // IMPORTANT: Update file name if needed
            guard let url = Bundle.main.url(forResource: "sample.m4a", withExtension: nil) else {
                print("Error: Audio file not found in onAppear.")
                return
            }
            playerManager.setupPlayer(url: url)
             // Initialize slider value
             currentSliderValue = playerManager.currentTime
        }
        .onDisappear {
            playerManager.stopAndCleanup()
        }
    }

    // --- Helper Functions --- 
    
    private func copyTranscription() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcriptionText, forType: .string)
        print("Transcription copied to clipboard.")
    }
    
    // Helper to format time like MM:SS
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
