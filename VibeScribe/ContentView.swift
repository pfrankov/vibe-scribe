//
//  ContentView.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI
import AVFoundation // Import AVFoundation
#if os(macOS)
import AVKit // Make sure we have AVKit for AVCaptureDevice on macOS
import Foundation // For Process
#endif

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
    let id: UUID
    let name: String
    let fileURL: URL? // URL to the actual audio file
    // Add sample date and duration for UI display (can be replaced with real data later)
    let date: Date
    let duration: TimeInterval // Will be determined after recording
    let hasTranscription: Bool // Will be false initially

    // Initializer for existing sample data (without fileURL)
    init(id: UUID = UUID(), name: String, date: Date = Date(), duration: TimeInterval = Double.random(in: 30...300), hasTranscription: Bool = Bool.random(), fileURL: URL? = nil) {
        self.id = id
        self.name = name
        self.date = date
        self.duration = duration
        self.hasTranscription = hasTranscription
        self.fileURL = fileURL
    }

    // Convenience initializer for newly created recordings
    init(name: String, fileURL: URL, duration: TimeInterval) {
        self.init(name: name, date: Date(), duration: duration, hasTranscription: false, fileURL: fileURL)
    }
}

// Helper to format duration
func formatDuration(_ duration: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: duration) ?? "0s"
}

// --- Audio Recorder Logic --- 

class AudioRecorderManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0.0
    @Published var error: Error? = nil // To report errors

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var audioFileURL: URL?

    // Get the directory to save recordings
    private func getRecordingsDirectory() -> URL {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupportURL = urls.first else {
            fatalError("Could not find Application Support directory.") // Handle more gracefully in production
        }
        
        // Append your app's bundle identifier and a 'Recordings' subdirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "VibeScribeApp"
        let recordingsURL = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("Recordings")

        // Create the directory if it doesn't exist
        if !fileManager.fileExists(atPath: recordingsURL.path) {
            do {
                try fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true, attributes: nil)
                print("Created recordings directory at: \(recordingsURL.path)")
            } catch {
                fatalError("Could not create recordings directory: \(error.localizedDescription)")
            }
        }
        return recordingsURL
    }

    // Setup the audio recorder
    private func setupRecorder() -> Bool {
        #if os(iOS)
        // iOS specific code for setting up audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true)
            print("Audio session activated on iOS.")
        } catch {
            print("Error setting up iOS audio session: \(error.localizedDescription)")
            self.error = error
            return false
        }
        #else
        // macOS doesn't require AVAudioSession setup for basic recording
        print("Setting up recorder on macOS (no AVAudioSession needed).")
        #endif
        
        do {
            // --- Updated Recording Settings to use AAC (more compatible) ---
            let recordingSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),   // Changed to AAC format 
                AVSampleRateKey: 44100,                     // Standard rate
                AVNumberOfChannelsKey: 1,                   // Mono
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue // For AAC
            ]

            // Create a unique file name with .m4a extension
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
            let dateString = dateFormatter.string(from: Date())
            let fileName = "recording_\(dateString).m4a" // Changed extension back to m4a
            audioFileURL = getRecordingsDirectory().appendingPathComponent(fileName)

            guard let url = audioFileURL else {
                print("Error: Audio File URL is nil.")
                self.error = NSError(domain: "AudioRecorderError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio file URL."])
                return false
            }
            
            print("Attempting to record to: \(url.path)")

            audioRecorder = try AVAudioRecorder(url: url, settings: recordingSettings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true // Enable metering if you want to show levels
            
            if audioRecorder?.prepareToRecord() == true {
                 print("Audio recorder prepared successfully.")
                 return true
             } else {
                 print("Error: Audio recorder failed to prepare.")
                 self.error = NSError(domain: "AudioRecorderError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio recorder failed to prepare."])
                 return false
             }

        } catch {
            print("Error setting up audio recorder: \(error.localizedDescription)")
            self.error = error
            #if os(iOS)
            // Attempt to deactivate session on error for iOS
            try? AVAudioSession.sharedInstance().setActive(false)
            #endif
            return false
        }
    }

    // Most minimal possible implementation
    func startRecording() {
        // Check if already recording
        if audioRecorder?.isRecording == true {
            print("Already recording.")
            return
        }

        // Clear previous error
        self.error = nil
        
        print("Attempting to start recording...") // Updated log message

        // Setup the recorder
        if !setupRecorder() {
            // Error should already be set by setupRecorder()
            print("Failed to setup recorder.")
            isRecording = false // Ensure state is correct
            return
        }

        // Recorder should be non-nil if setupRecorder returned true
        guard let recorder = audioRecorder else {
            print("Error: Recorder is nil after successful setup.")
            self.error = NSError(domain: "AudioRecorderError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Internal error: Recorder became nil."])
            isRecording = false
            return
        }

        // Attempt to start recording
        if recorder.record() {
            isRecording = true
            startTimer() // Start updating recordingTime
            print("Recording started successfully.")
        } else {
            // Recording failed to start, even though setup was successful
            print("Error: recorder.record() returned false.")
            self.error = NSError(domain: "AudioRecorderError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording after setup."])
            isRecording = false
            // Clean up recorder instance if start failed? Maybe not necessary here, handled by stop/cancel.
            // audioRecorder = nil 
        }
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard let recorder = audioRecorder, isRecording else { return nil }

        print("Stopping recording...")
        let duration = recorder.currentTime
        recorder.stop()
        stopTimer()
        isRecording = false
        recordingTime = 0.0
        let savedURL = audioFileURL
        audioRecorder = nil // Release the recorder
        audioFileURL = nil // Clear the file URL
        
        #if os(iOS)
        // Deactivate the audio session after recording on iOS
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("Audio session deactivated.")
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
            // Don't necessarily set self.error here, as recording succeeded
        }
        #endif

        if let url = savedURL {
            print("Recording stopped. File saved at: \(url.path), Duration: \(duration)")
            return (url, duration)
        } else {
            print("Error: Recorded file URL was nil after stopping.")
            self.error = NSError(domain: "AudioRecorderError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Recorded file URL was lost."])
            return nil
        }
    }

    func cancelRecording() {
        guard let recorder = audioRecorder, isRecording else { return }
        
        print("Cancelling recording...")
        recorder.stop()
        stopTimer()
        isRecording = false
        recordingTime = 0.0

        // Delete the partially recorded file
        if let url = audioFileURL {
            print("Deleting temporary file: \(url.path)")
            recorder.deleteRecording() // This deletes the file at recorder's URL
        } else {
            print("Warning: Could not find file URL to delete for cancelled recording.")
        }
        
        audioRecorder = nil
        audioFileURL = nil
        error = nil // Clear error state on cancellation
        
        #if os(iOS)
        // Deactivate the audio session on iOS
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("Audio session deactivated.")
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
        }
        #endif
    }

    private func startTimer() {
        stopTimer() // Ensure no duplicates
        recordingTime = 0.0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, self.isRecording else {
                self?.stopTimer() // Stop if self is nil or no recorder/not recording
                return
            }
            self.recordingTime = recorder.currentTime
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - AVAudioRecorderDelegate Methods
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully.")
            // This might happen due to interruption or error. Stop timer etc.
            stopTimer()
            isRecording = false
            recordingTime = 0.0
            self.error = NSError(domain: "AudioRecorderError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Recording did not finish successfully."])
            
            #if os(iOS)
            // Deactivate session on iOS
            do {
                try AVAudioSession.sharedInstance().setActive(false)
                print("Audio session deactivated after unsuccessful recording.")
            } catch {
                print("Error deactivating audio session: \(error.localizedDescription)")
            }
            #endif
        }
        // Note: We handle successful completion within stopRecording()
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Audio recorder encode error: \(error?.localizedDescription ?? "Unknown error")")
        stopTimer()
        isRecording = false
        recordingTime = 0.0
        self.error = error ?? NSError(domain: "AudioRecorderError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Encoding error occurred."])
        
        #if os(iOS)
        // Deactivate session on iOS
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            print("Audio session deactivated after encode error.")
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
        }
        #endif
    }
    
    deinit {
        // Ensure cleanup if the manager is deallocated unexpectedly
        stopTimer()
        if isRecording {
            cancelRecording() // Cancel if still recording
        }
        print("AudioRecorderManager deinitialized")
    }
}

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedRecord: Record? = nil // State to manage which detail view to show
    @State private var isShowingRecordingSheet = false // State for the recording sheet

    // Sample data for the list - Now with explicit initializers
    @State private var records = [
        Record(name: "Meeting Notes 2024-04-21", duration: 125, hasTranscription: true),
        Record(name: "Idea Brainstorm", duration: 280, hasTranscription: false),
        Record(name: "Lecture Recording", duration: 45, hasTranscription: false),
        Record(name: "Quick Memo", duration: 190, hasTranscription: true),
        Record(name: "Project Update", duration: 65, hasTranscription: false)
    ]

    // Date formatter for default recording names
    private var recordingNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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
                    RecordsListView(
                        records: $records,
                        selectedRecord: $selectedRecord,
                        showRecordingSheet: $isShowingRecordingSheet,
                        onDelete: deleteRecord
                    )
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
        // Sheet for Record Detail
        .sheet(item: $selectedRecord) { record in
            RecordDetailView(record: record)
                .frame(minWidth: 400, minHeight: 450)
        }
        // Sheet for Recording
        .sheet(isPresented: $isShowingRecordingSheet) {
            // Updated closure signature
            RecordingView { savedURL, duration in
                isShowingRecordingSheet = false // Dismiss sheet
                guard let url = savedURL else { 
                    print("Recording was cancelled or failed.")
                    return 
                }
                
                // Create a default name
                let defaultName = "Recording \(recordingNameFormatter.string(from: Date()))"
                
                // Create and add the new record
                let newRecord = Record(name: defaultName, fileURL: url, duration: duration ?? 0.0)
                records.append(newRecord)
                print("Added new record: \(newRecord.name)")
            }
            .frame(minWidth: 350, minHeight: 300) // Adjusted size slightly
        }
    }

    // --- Record Management Functions ---

    // Function to delete a record
    private func deleteRecord(recordToDelete: Record) {
        // 1. Delete the associated audio file if it exists
        if let fileURL = recordToDelete.fileURL {
            do {
                // Check if file exists before attempting deletion
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                    print("Successfully deleted audio file: \(fileURL.path)")
                } else {
                    print("Audio file not found, skipping deletion: \(fileURL.path)")
                }
            } catch {
                print("Error deleting audio file \(fileURL.path): \(error.localizedDescription)")
                // Decide if you want to proceed with removing the record from the list
                // even if file deletion fails. For now, we will.
            }
        } else {
            print("Record \(recordToDelete.name) has no associated fileURL.")
        }

        // 2. Remove the record from the state array
        // Use removeAll(where:) for safer removal based on id
        records.removeAll { $0.id == recordToDelete.id }
        print("Removed record from list: \(recordToDelete.name)")

        // 3. If the deleted record was currently selected, deselect it
        if selectedRecord?.id == recordToDelete.id {
            selectedRecord = nil
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
    @Binding var records: [Record]
    @Binding var selectedRecord: Record? // Binding to control the detail sheet presentation
    @Binding var showRecordingSheet: Bool // Binding to control the recording sheet
    var onDelete: (Record) -> Void // Closure to handle deletion

    var body: some View {
        VStack {
            // Header with New Recording Button
            HStack {
                Text("All Recordings").font(.title2).bold()
                Spacer()
                Button {
                    showRecordingSheet = true
                } label: {
                    Label("New Recording", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PlainButtonStyle()) // Use plain style for consistency
                .labelStyle(.titleAndIcon) // Show both title and icon
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom, 5)

            // Use a Group to switch between List and Empty State
            Group {
                if records.isEmpty {
                    VStack {
                        Spacer() // Pushes content to center
                        Image(systemName: "mic.slash") // More relevant icon
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)
                        Text("No recordings yet.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap '+' to create your first recording.") // Actionable text
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
                                    selectedRecord = record // Set the selected record to show the detail sheet
                                }
                                // Add Context Menu for Delete Action
                                .contextMenu {
                                    Button(role: .destructive) {
                                        onDelete(record) // Call the delete closure passed from ContentView
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(InsetListStyle()) // A slightly more modern list style
                    // Removed top padding here, handled by VStack container now
                }
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
    @State private var isEditingSlider = false // Track if user is scrubbing

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
                    
                    // Progress Slider - Updated Logic
                    Slider(
                        value: $playerManager.currentTime, // Bind directly to player's current time for display
                        in: 0...(playerManager.duration > 0 ? playerManager.duration : 1.0),
                        onEditingChanged: { editing in
                            isEditingSlider = editing // Track scrubbing state
                            if editing {
                                playerManager.scrubbingStarted() // Tell manager scrubbing started
                            } else {
                                // Seek when scrubbing ends (using the current value from playerManager)
                                playerManager.seek(to: playerManager.currentTime)
                            }
                        }
                    )
                    // Remove the complex onChange modifier, direct binding handles updates when not editing
                    // .onChange(of: playerManager.currentTime) { oldValue, newValue in ... }


                    // Time Label
                    // Display player's current time / total duration
                    Text("\(formatTime(playerManager.currentTime)) / \(formatTime(playerManager.duration))")
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
            // --- Refined File Loading Logic ---
            guard let fileURL = record.fileURL else {
                print("Error: Record '\(record.name)' has no associated fileURL.")
                // Optionally disable player controls or show UI error
                // For now, we just prevent player setup
                return // Exit early
            }

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Error: Audio file for record '\(record.name)' not found at path: \(fileURL.path)")
                // Optionally disable player controls or show UI error
                return // Exit early
            }

            print("Loading audio from: \(fileURL.path)")
            playerManager.setupPlayer(url: fileURL)
            // No need to initialize currentSliderValue here anymore
            // currentSliderValue = playerManager.currentTime
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

// --- Updated Recording View --- 
struct RecordingView: View {
    @Environment(\.dismiss) var dismiss
    // Updated closure: returns optional URL and TimeInterval
    var onComplete: (URL?, TimeInterval?) -> Void 

    @StateObject private var recorderManager = AudioRecorderManager()
    // Removed @State private var isRecording - now managed by recorderManager

    var body: some View {
        VStack(spacing: 20) {
            // Title reflects recorder state more dynamically
            Text(recorderManager.isRecording ? "Recording..." : recorderManager.error == nil ? "Preparing..." : "Error") // Updated title logic
                .font(.title)

            // Display recording time
            Text(formatTime(recorderManager.recordingTime))
                .font(.title2)
                .monospacedDigit() // Ensures stable width
                .padding(.bottom)

            // Microphone icon indicates state
            Image(systemName: recorderManager.isRecording ? "mic.fill" : "mic.slash.fill") // Use slash when not recording or error
                .font(.system(size: 60))
                // Color indication: red when recording, orange on error, secondary otherwise
                .foregroundColor(recorderManager.isRecording ? .red : (recorderManager.error != nil ? .orange : .secondary))
                .padding()

            // Display error message if any
            if let error = recorderManager.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .font(.caption)
                    .lineLimit(2)
                    .padding(.horizontal)
            }

            HStack {
                // --- Updated Button Logic ---
                // The main button is now always "Stop" but disabled until recording actually starts
                Button("Stop") {
                    // Stop recording and call completion handler
                    if let result = recorderManager.stopRecording() {
                         onComplete(result.url, result.duration)
                     } else {
                         // Handle error if stopRecording failed (error is likely already set in manager)
                         onComplete(nil, nil)
                     }
                    dismiss() // Dismiss the sheet after stopping
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red) // Always red as it's the "Stop" action
                // Disable Stop button if not recording OR if recording time is too short (prevents accidental taps) OR if there's an error
                .disabled(!recorderManager.isRecording || recorderManager.recordingTime < 0.5 || recorderManager.error != nil)

                // Cancel Button (Always visible, but primary action changes)
                // If recording: Cancels the recording
                // If not recording (e.g., during setup or error): Closes the sheet
                Button(recorderManager.isRecording ? "Cancel" : "Close") {
                    if recorderManager.isRecording {
                        recorderManager.cancelRecording()
                        onComplete(nil, nil) // Indicate cancellation
                    } else {
                        // If not recording (e.g., failed to start), just close the sheet
                        onComplete(nil, nil) 
                    }
                    dismiss() // Close the sheet
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            Spacer() // Push controls up
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // --- Start recording automatically when the view appears ---
            print("RecordingView appeared. Attempting to start recording.")
            recorderManager.startRecording()
        }
        .onDisappear {
            // Ensure recording is stopped/cancelled if the view disappears unexpectedly
            // This might happen if the user closes the window or the app quits
            if recorderManager.isRecording {
                print("RecordingView disappeared while recording. Cancelling.")
                // We call cancel which also cleans up the file
                recorderManager.cancelRecording() 
                // We might want to inform the caller, but onComplete might not be valid anymore
                // onComplete(nil, nil) // Be cautious calling this here
            }
        }
    }
    
    // Re-use the time formatter from RecordDetailView
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
}
