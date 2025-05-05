//
//  SystemAudioRecorderManager.swift
//  VibeScribe
//
//  Created by Your Name on \(Date()) // Or replace with actual logic if needed
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine // For ObservableObject

// Availability check for the entire class
@MainActor // <<< Add @MainActor
@available(macOS 12.3, *)
class SystemAudioRecorderManager: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {

    @Published var isRecording = false
    @Published var error: Error?
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10) // Array to store system audio levels for visualization

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var audioSettings: [String: Any]?
    private var outputURL: URL?

    // Start recording system audio
    func startRecording(outputURL: URL) {
        guard !isRecording else {
            print("SystemAudioRecorderManager: Already recording.")
            return
        }

        self.outputURL = outputURL
        self.error = nil // Reset error on new start

        // Ensure directory exists
        let directory = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("SystemAudioRecorderManager: Failed to create directory: \\(error)")
            self.error = error
            return
        }

        // Fetch available content
        Task { // Use Task for async operation
             print("SystemAudioRecorderManager: Task started.")
            do {
                 print("SystemAudioRecorderManager: Attempting to get SCShareableContent.current...")
                // Filter for displays. We need *a* source for the stream, even if audio-only.
                // Capture audio from all displays/system.
                let availableContent = try await SCShareableContent.current
                 print("SystemAudioRecorderManager: Got SCShareableContent. Display count: \(availableContent.displays.count)")
                guard let display = availableContent.displays.first else {
                     print("SystemAudioRecorderManager: No displays found!")
                     throw NSError(domain: "SystemAudioRecorderManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No displays found to capture audio from."])
                }
                 print("SystemAudioRecorderManager: Using display: \(display.displayID)")

                // Configuration for the stream
                let config = SCStreamConfiguration()
                config.width = 2 // Minimal width/height needed even for audio
                config.height = 2
                config.capturesAudio = true
                config.showsCursor = false // Hide cursor for audio-only capture
                config.excludesCurrentProcessAudio = true // Don't record VibeScribe's own audio playback

                // Filter for the selected display (required for stream setup)
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                 print("SystemAudioRecorderManager: Filter and config created.")

                // Create the stream
                 print("SystemAudioRecorderManager: Creating SCStream...")
                stream = SCStream(filter: filter, configuration: config, delegate: self)
                 print("SystemAudioRecorderManager: SCStream created.")
                
                // Add output handler
                 print("SystemAudioRecorderManager: Adding stream output...")
                try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
                // Добавим пустой обработчик для видео фреймов, чтобы избежать ворнингов
                try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .utility))
                 print("SystemAudioRecorderManager: Stream outputs added.")

                // Start capture
                 print("SystemAudioRecorderManager: Attempting stream.startCapture()...")
                try await stream?.startCapture()
                 print("SystemAudioRecorderManager: stream.startCapture() completed.")

                DispatchQueue.main.async {
                    self.isRecording = true
                    print("SystemAudioRecorderManager: Started recording system audio.")
                }

            } catch {
                 DispatchQueue.main.async {
                     print("SystemAudioRecorderManager: Failed to start recording: \\(error.localizedDescription)")
                     self.error = error
                     self.isRecording = false // Ensure state is correct on failure
                 }
            }
        }
    }

    // Stop recording system audio
    func stopRecording() {
        // No Task needed here as @MainActor ensures it's on main thread
        guard isRecording else {
            print("SystemAudioRecorderManager: Not recording.")
            return
        }

        guard let stream = stream else {
            print("SystemAudioRecorderManager: Stream is nil, cannot stop.")
            self.isRecording = false // Correct state if stream somehow nil
            return
        }

        // Stopping the stream needs to be async
        Task {
            do {
                try await stream.stopCapture()
                // Update state back on the main actor after async call completes
                self.stream = nil
                self.audioFile = nil // Ensure file is closed/nil
                self.isRecording = false
                print("SystemAudioRecorderManager: Stopped recording system audio.")
            } catch {
                print("SystemAudioRecorderManager: Failed to stop stream: \\(error.localizedDescription)")
                // Still set recording to false, but maybe log error
                self.error = error
                self.stream = nil
                self.audioFile = nil
                self.isRecording = false
            }
        }
    }

    // MARK: - SCStreamOutput Delegate

    nonisolated
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Обрабатываем видео фреймы
        if type == .screen {
            processVideoSampleBuffer(sampleBuffer)
            return
        }
        
        // Обрабатываем аудио фреймы
        guard type == .audio else { return }

        // Check data readiness first (non-isolated)
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            print("SystemAudioRecorderManager: [Non-isolated] Sample buffer data is not ready.")
            return
        }

        // Calculate audio levels from the sample buffer
        updateAudioLevels(from: sampleBuffer)

        // Get format description and ASBD (non-isolated)
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
            print("SystemAudioRecorderManager: [Non-isolated] Could not get audio format description.")
            Task { @MainActor in // Dispatch error setting and stop to main actor
                self.error = NSError(domain: "SystemAudioRecorderManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get audio format."])
                self.stopRecording()
            }
            return
        }
        var streamDesc = asbdPtr.pointee
        print("""
        SystemAudioRecorderManager: [Non-isolated] Received Buffer. ASBD Details:
            SampleRate: \(streamDesc.mSampleRate)
            FormatID: \(streamDesc.mFormatID) (\(fourCCString(from: streamDesc.mFormatID)))
            FormatFlags: \(streamDesc.mFormatFlags)
            BytesPerPacket: \(streamDesc.mBytesPerPacket)
            FramesPerPacket: \(streamDesc.mFramesPerPacket)
            BytesPerFrame: \(streamDesc.mBytesPerFrame)
            ChannelsPerFrame: \(streamDesc.mChannelsPerFrame)
            BitsPerChannel: \(streamDesc.mBitsPerChannel)
        """)

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))

        // --- Main Actor Task for File I/O and State Updates ---
        Task { @MainActor in
            // Re-check if still recording, in case stop was called concurrently
            guard self.isRecording else { return }
            
            // Initialize audio file on first buffer (on MainActor)
            if audioFile == nil {
                guard let outputURL = self.outputURL else {
                    print("SystemAudioRecorderManager: Output URL is nil.")
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Output URL not set."])
                    self.stopRecording()
                    return
                }

                guard let avFormat = AVAudioFormat(streamDescription: &streamDesc) else {
                    print("SystemAudioRecorderManager: Could not create AVAudioFormat.")
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat."])
                    self.stopRecording()
                    return
                }

                do {
                    audioFile = try AVAudioFile(forWriting: outputURL, settings: avFormat.settings)
                    print("SystemAudioRecorderManager: Audio file initialized successfully at \\(outputURL.path) with format: \\(avFormat)")
                } catch {
                    print("SystemAudioRecorderManager: Failed to create AVAudioFile: \\(error)")
                    self.error = error
                    self.stopRecording()
                    return
                }
            }

            // --- Process and Write Audio Buffer (on MainActor) --- 
            guard let audioFile = audioFile else {
                print("SystemAudioRecorderManager: Audio file is nil, cannot write buffer.")
                return
            }

            do {
                // SIMPLER IMPLEMENTATION: Use AVAudioPCMBuffer initialization with CMSampleBuffer
                guard let pcmBuffer = try createPCMBufferFrom(sampleBuffer: sampleBuffer,
                                                             format: audioFile.processingFormat,
                                                             frameCount: frameCount) else {
                    print("SystemAudioRecorderManager: Failed to create PCM buffer from sample buffer")
                    return
                }

                // Write the filled AVAudioPCMBuffer
                try audioFile.write(from: pcmBuffer)

            } catch {
                // Catch Swift errors, e.g., from audioFile.write
                print("SystemAudioRecorderManager: [MainActor] Failed to process or write audio buffer (Swift Error): \(error)")
                self.error = error // Optionally set error state
            }
        }
    }

    // Обработчик видео фреймов - просто игнорируем их, но предотвращаем ошибки
    nonisolated
    func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Пустая реализация - ничего не делаем с видео фреймами
        // Просто позволяем ScreenCaptureKit иметь место для их отправки
    }

    // New helper function to create an AVAudioPCMBuffer from a CMSampleBuffer
    private nonisolated func createPCMBufferFrom(sampleBuffer: CMSampleBuffer, 
                                               format: AVAudioFormat,
                                               frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        // Create a new buffer with the right format
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        pcmBuffer.frameLength = frameCount
        
        // Get audio buffer list from the sample buffer
        
        // Instead of using the CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer that's failing,
        // try a different approach to extract audio data
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            print("SystemAudioRecorderManager: Failed to get data buffer from sample buffer")
            return nil
        }
        
        var dataLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        // Lock the data buffer to get direct access to its memory
        let status = CMBlockBufferGetDataPointer(dataBuffer,
                                              atOffset: 0,
                                              lengthAtOffsetOut: nil,
                                              totalLengthOut: &dataLength,
                                              dataPointerOut: &dataPointer)
        
        if status != kCMBlockBufferNoErr {
            print("SystemAudioRecorderManager: Failed to get data pointer from block buffer: \(status)")
            return nil
        }
        
        // Fill the PCM buffer with the data from the CMBlockBuffer
        guard let dataPtr = dataPointer, let pcmBufferData = pcmBuffer.floatChannelData else {
            return nil
        }
        
        let channelCount = Int(format.channelCount)
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        
        // Copy data for each channel
        for channel in 0..<channelCount {
            // First channel
            let channelData = pcmBufferData[channel]
            
            // Copy the interleaved samples for this channel
            for frame in 0..<Int(frameCount) {
                let offset = frame * Int(bytesPerFrame)
                if offset + 4 <= dataLength { // Ensure we don't read past the buffer
                    let sample = dataPtr.advanced(by: offset + channel * 4).withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
                    channelData[frame] = sample
                }
            }
        }
        
        return pcmBuffer
    }

    // Helper function to convert FourCC code to String (add this outside the delegate method)
    private nonisolated func fourCCString(from formatID: AudioFormatID) -> String {
        let bytes: [CChar] = [
            CChar(truncatingIfNeeded: (formatID >> 24) & 0xFF),
            CChar(truncatingIfNeeded: (formatID >> 16) & 0xFF),
            CChar(truncatingIfNeeded: (formatID >> 8) & 0xFF),
            CChar(truncatingIfNeeded: formatID & 0xFF),
            0 // Null terminator
        ]
        return String(cString: bytes)
    }

    // MARK: - SCStreamDelegate

    nonisolated
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Dispatch state updates to the main actor
        Task { @MainActor in
            print("SystemAudioRecorderManager: Stream stopped with error: \\(error.localizedDescription)")
            self.error = error
            // Ensure state is reset
            self.stream = nil
            self.audioFile = nil
            self.isRecording = false
        }
    }

    // New method to calculate and update audio levels from the sample buffer
    private nonisolated func updateAudioLevels(from sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var dataLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(dataBuffer,
                                             atOffset: 0,
                                             lengthAtOffsetOut: nil,
                                             totalLengthOut: &dataLength,
                                             dataPointerOut: &dataPointer)
        
        if status != kCMBlockBufferNoErr || dataPointer == nil { return }
        
        // Get the audio data to calculate RMS power
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
        let bytesPerFrame = asbd.pointee.mBytesPerFrame
        
        // Calculate RMS power (average of squared samples)
        var sumSquares: Float = 0.0
        let samples = UnsafeMutableRawPointer(dataPointer!)
        
        // Process each frame
        for frame in 0..<frameCount {
            // Process each channel in the frame
            for channel in 0..<channelCount {
                let offset = Int(bytesPerFrame) * frame + channel * 4 // Assuming 32-bit float samples
                if offset + 4 <= dataLength {
                    let sampleValue = samples.load(fromByteOffset: offset, as: Float.self)
                    sumSquares += sampleValue * sampleValue
                }
            }
        }
        
        // Calculate RMS and convert to level (0...1)
        let rms = sqrtf(sumSquares / Float(frameCount * channelCount))
        // Normalize and apply some scaling for better visualization
        let normalizedLevel = min(1.0, max(0.0, rms * 5.0)) // Scale factor can be adjusted
        
        // Update the levels on the main thread
        Task { @MainActor in
            // Remove oldest value and add new one
            self.audioLevels.removeFirst()
            self.audioLevels.append(normalizedLevel)
        }
    }
}