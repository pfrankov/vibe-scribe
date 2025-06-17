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
import Darwin // For log10

// Availability check for the entire class
@MainActor // <<< Add @MainActor
@available(macOS 12.3, *)
class SystemAudioRecorderManager: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {

    @Published var isRecording = false
    @Published var error: Error?
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10) // Array to store system audio levels for visualization

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?

    // Check if screen capture permissions are available
    func hasScreenCapturePermission() async -> Bool {
        do {
            _ = try await SCShareableContent.current
            return true
        } catch {
            Logger.error("Screen capture permission not available", error: error, category: .audio)
            return false
        }
    }

    // Start recording system audio
    func startRecording(outputURL: URL) {
        Logger.info("Attempting to start system audio recording", category: .audio)
        guard !isRecording else {
            Logger.warning("Already recording system audio", category: .audio)
            return
        }

        self.outputURL = outputURL
        self.error = nil // Reset error on new start

        // Ensure directory exists
        let directory = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.error("Failed to create directory for system audio recording", error: error, category: .audio)
            self.error = error
            return
        }

        // Fetch available content
        Task { // Use Task for async operation
            do {
                let availableContent = try await SCShareableContent.current
                guard let display = availableContent.displays.first else {
                     NSLog("SystemAudioRecorderManager: No displays found!")
                     throw NSError(domain: "SystemAudioRecorderManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No displays found to capture audio from."])
                }

                // Configuration for the stream
                let config = SCStreamConfiguration()
                config.width = 2 // Minimal width/height needed even for audio
                config.height = 2
                config.capturesAudio = true
                config.showsCursor = false // Hide cursor for audio-only capture
                config.excludesCurrentProcessAudio = true // Don't record VibeScribe's own audio playback

                // Filter for the selected display (required for stream setup)
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

                stream = SCStream(filter: filter, configuration: config, delegate: self)
                
                let audioSampleHandlerQueue = DispatchQueue(label: "com.vibescribe.audioSampleHandlerQueue")
                try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioSampleHandlerQueue)
                try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .utility))

                try await stream?.startCapture()

                DispatchQueue.main.async {
                    self.isRecording = true
                    NSLog("SystemAudioRecorderManager: Started recording system audio.")
                }

            } catch {
                 DispatchQueue.main.async {
                     NSLog("SystemAudioRecorderManager: Failed to start recording: \(error.localizedDescription). Error: \(error)")
                     self.error = error
                     self.isRecording = false // Ensure state is correct on failure
                 }
            }
        }
    }

    // Stop recording system audio
    func stopRecording() {
        NSLog("SystemAudioRecorderManager: Attempting to stop recording.")
        guard isRecording else {
            return
        }

        guard let stream = stream else {
            NSLog("SystemAudioRecorderManager: Stream is nil, cannot stop. Setting isRecording to false.")
            self.isRecording = false 
            return
        }

        Task {
            do {
                try await stream.stopCapture()
                self.stream = nil
                self.audioFile = nil
                self.isRecording = false
                NSLog("SystemAudioRecorderManager: Stopped recording system audio.")
            } catch {
                NSLog("SystemAudioRecorderManager: Failed to stop stream: \(error.localizedDescription). Error: \(error)")
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
        // Process video frames
        if type == .screen {
            processVideoSampleBuffer(sampleBuffer)
            return
        }
        
        // Process audio frames
        guard type == .audio else { return }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        updateAudioLevels(from: sampleBuffer)

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            NSLog("SystemAudioRecorderManager: [Non-isolated] Could not get audio format description.")
            Task { @MainActor in 
                self.error = NSError(domain: "SystemAudioRecorderManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get audio format."])
                self.stopRecording()
            }
            return
        }
        var streamDesc = asbdPtr.pointee

        let frameCount = AVAudioFrameCount(numSamples)

        Task { @MainActor in
            guard self.isRecording else {
                return
            }
            
            if self.audioFile == nil {
                guard let outputURL = self.outputURL else {
                    NSLog("SystemAudioRecorderManager: [MainActor Task] Output URL is nil during init.")
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Output URL not set."])
                    self.stopRecording()
                    return
                }

                guard let avFormat = AVAudioFormat(streamDescription: &streamDesc) else {
                    NSLog("SystemAudioRecorderManager: [MainActor Task] Could not create AVAudioFormat from streamDesc.")
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat."])
                    self.stopRecording()
                    return
                }

                do {
                    self.audioFile = try AVAudioFile(forWriting: outputURL, settings: avFormat.settings)
                } catch {
                    NSLog("SystemAudioRecorderManager: [MainActor Task] Failed to create AVAudioFile: \(error.localizedDescription). Error: \(error)")
                    self.error = error
                    self.stopRecording()
                    return
                }
            }

            guard let audioFile = self.audioFile else {
                return
            }

            do {
                guard let pcmBuffer = try createPCMBufferFrom(sampleBuffer: sampleBuffer,
                                                             format: audioFile.processingFormat,
                                                             frameCount: frameCount) else {
                    NSLog("SystemAudioRecorderManager: [MainActor Task] Failed to create PCM buffer from sample buffer.")
                    return
                }

                try audioFile.write(from: pcmBuffer)

            } catch {
                NSLog("SystemAudioRecorderManager: [MainActor Task] Failed to process or write audio buffer (Swift Error): \(error.localizedDescription). Error: \(error)")
                self.error = error
            }
        }
    }

    // Video frame handler - simply ignore them but prevent errors
    nonisolated
    func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Empty implementation - we don't need video frames
        // Just allow ScreenCaptureKit to have a place to send them
    }

    // New helper function to create an AVAudioPCMBuffer from a CMSampleBuffer
    private nonisolated func createPCMBufferFrom(sampleBuffer: CMSampleBuffer, 
                                               format: AVAudioFormat,
                                               frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard let sourceFormatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let _ = CMAudioFormatDescriptionGetStreamBasicDescription(sourceFormatDesc) else {
            NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] Failed to get source ASBD from sampleBuffer.")
            return nil
        }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] Failed to create AVAudioPCMBuffer with target format.")
            return nil
        }
        pcmBuffer.frameLength = frameCount
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] Failed to get data buffer (CMBlockBuffer).")
            return nil
        }
        
        var dataLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        
        let status = CMBlockBufferGetDataPointer(dataBuffer,
                                              atOffset: 0,
                                              lengthAtOffsetOut: &dataLength,
                                              totalLengthOut: nil,
                                              dataPointerOut: &dataPointer)
        
        if status != kCMBlockBufferNoErr {
            NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] Failed to get data pointer from block buffer: \(status).")
            return nil
        }
        
        guard let sourceDataPtr = dataPointer else {
            NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] dataPointer is nil after CMBlockBufferGetDataPointer.")
            return nil
        }
        
        let targetChannelCount = Int(format.channelCount)
        let targetIsFloat = format.commonFormat == .pcmFormatFloat32

        if targetIsFloat, let targetFloatChannelData = pcmBuffer.floatChannelData {
            let samplesPerChannel = Int(frameCount)

            for channel in 0..<targetChannelCount {
                let destinationChannelBuffer = targetFloatChannelData[channel]
                let sourceChannelMemoryOffset = channel * samplesPerChannel * MemoryLayout<Float>.size

                for frame in 0..<samplesPerChannel {
                    let sourceSampleMemoryOffsetInChannel = frame * MemoryLayout<Float>.size
                    let finalSourceSampleMemoryOffset = sourceChannelMemoryOffset + sourceSampleMemoryOffsetInChannel
                    
                    if finalSourceSampleMemoryOffset + MemoryLayout<Float>.size <= dataLength {
                        let sampleValue = sourceDataPtr.advanced(by: finalSourceSampleMemoryOffset).withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
                        destinationChannelBuffer[frame] = sampleValue
                    } else {
                        NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] WARN: Read out of bounds or dataLength insufficient. channel=\(channel), frame=\(frame), offset=\(finalSourceSampleMemoryOffset), dataLength=\(dataLength). Filling with 0.")
                        destinationChannelBuffer[frame] = 0.0 
                    }
                }
            }
        } else if format.commonFormat == .pcmFormatInt16, let targetInt16ChannelData = pcmBuffer.int16ChannelData {
            NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] Using int16ChannelData. CAUTION: Untested/Unexpected path for float source.")
            let samplesPerChannel = Int(frameCount)
            for channel in 0..<targetChannelCount {
                let destinationChannelBuffer = targetInt16ChannelData[channel]
                for frame in 0..<samplesPerChannel {
                    destinationChannelBuffer[frame] = 0 
                }
            }
        } else {
             NSLog("SystemAudioRecorderManager: [createPCMBufferFrom] PCM buffer data pointers (float/int16) are nil or format is unsupported for direct copy. Target Format: \(format.commonFormat).")
             return nil // Cannot proceed if we don't have the channel data pointers
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
            NSLog("SystemAudioRecorderManager: Stream stopped with error: \(error.localizedDescription). Error: \(error)")
            self.error = error
            // Ensure state is reset
            self.stream = nil
            self.audioFile = nil
            self.isRecording = false
        }
    }

    // New method to calculate and update audio levels from the sample buffer
    private nonisolated func updateAudioLevels(from sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        
        var dataLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(dataBuffer,
                                             atOffset: 0,
                                             lengthAtOffsetOut: &dataLength,
                                             totalLengthOut: nil,
                                             dataPointerOut: &dataPointer)
        
        if status != kCMBlockBufferNoErr || dataPointer == nil {
            return
        }
        
        // Get the audio data to calculate RMS power
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
            return
        }
        
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        if frameCount == 0 { return } // Avoid division by zero
        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
        if channelCount == 0 { return } // Avoid division by zero
        
        // Calculate RMS power (average of squared samples) with optimized sampling
        var sumSquares: Float = 0.0
        
        // Assuming audio data is 32-bit float (kAudioFormatLinearPCM + kAudioFormatFlagIsFloat)
        // This is typical for SCStreamOutputType.audio
        if (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && asbd.pointee.mBitsPerChannel == 32 {
            let floatDataPointer = UnsafeRawPointer(dataPointer!)!.assumingMemoryBound(to: Float.self)
            let sampleCount = frameCount * channelCount
            
            if dataLength < sampleCount * MemoryLayout<Float>.size {
                return
            }

            // Performance optimization: sample every 16th sample for level calculation
            // This reduces CPU usage while maintaining visual accuracy
            let sampleStep = max(1, sampleCount / 1024) // Sample at most 1024 points
            var actualSampleCount = 0
            
            for i in stride(from: 0, to: sampleCount, by: sampleStep) {
                let sampleValue = floatDataPointer[i]
                sumSquares += sampleValue * sampleValue
                actualSampleCount += 1
            }
            
            if actualSampleCount > 0 {
                sumSquares /= Float(actualSampleCount)
            }
        } else {
            Task { @MainActor in
                // Simplified logic: if array is full, remove first, then append.
                if self.audioLevels.count == 10 { // Assuming it's initialized with 10 items
                    self.audioLevels.removeFirst()
                }
                self.audioLevels.append(0.0) // Append a default/silent level
            }
            return
        }
        
        // Calculate RMS and convert to level (0...1)
        let rms = sqrtf(sumSquares)
        
        // Convert RMS to decibels for consistency with microphone levels
        let powerInDb = 20.0 * log10(Double(rms + 1e-10)) // Add epsilon to avoid log(0)
        
        // Use same normalization as microphone (typical range -10 to -30 dB for audio)
        let normalizedLevel = Float(min(1.0, max(0.0, (powerInDb + 50) / 50)))
        
        // Update the levels on the main thread
        Task { @MainActor in
            // Simplified logic: if array is full, remove first, then append.
            if self.audioLevels.count == 10 { // Assuming it's initialized with 10 items
            self.audioLevels.removeFirst()
            }
            self.audioLevels.append(normalizedLevel)
        }
    }
}