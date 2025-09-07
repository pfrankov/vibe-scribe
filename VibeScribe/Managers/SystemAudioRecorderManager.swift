import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import Darwin

@MainActor
class SystemAudioRecorderManager: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {

    @Published var isRecording = false
    @Published var error: Error?
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10)

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
        self.error = nil

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
        Task {
            do {
                let availableContent = try await SCShareableContent.current
                guard let display = availableContent.displays.first else {
                    Logger.error("No displays found to capture audio from.", category: .audio)
                    throw NSError(domain: "SystemAudioRecorderManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No displays found to capture audio from."])
                }

                // Configuration for the stream
                let config = SCStreamConfiguration()
                config.width = 2
                config.height = 2
                config.capturesAudio = true
                config.showsCursor = false
                config.excludesCurrentProcessAudio = true

                // Filter for the selected display (required for stream setup)
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

                stream = SCStream(filter: filter, configuration: config, delegate: self)

                let audioSampleHandlerQueue = DispatchQueue(label: "com.vibescribe.audioSampleHandlerQueue")
                try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioSampleHandlerQueue)
                try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .utility))

                try await stream?.startCapture()

                self.isRecording = true
                Logger.info("Started recording system audio", category: .audio)

            } catch {
                Logger.error("Failed to start system audio recording", error: error, category: .audio)
                self.error = error
                self.isRecording = false
            }
        }
    }

    // Stop recording system audio
    func stopRecording() {
        Logger.info("Attempting to stop system audio recording", category: .audio)
        guard isRecording else {
            return
        }

        guard let stream = stream else {
            Logger.warning("Stream is nil, cannot stop. Setting isRecording to false.", category: .audio)
            self.isRecording = false
            return
        }

        Task {
            do {
                try await stream.stopCapture()
                self.stream = nil
                self.audioFile = nil
                self.isRecording = false
                Logger.info("Stopped recording system audio", category: .audio)
            } catch {
                Logger.error("Failed to stop system audio recording", error: error, category: .audio)
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
            Logger.error("[Non-isolated] Could not get audio format description.", category: .audio)
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
                    Logger.error("[MainActor Task] Output URL is nil during init.", category: .audio)
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Output URL not set."])
                    self.stopRecording()
                    return
                }

                guard let avFormat = AVAudioFormat(streamDescription: &streamDesc) else {
                    Logger.error("[MainActor Task] Could not create AVAudioFormat from streamDesc.", category: .audio)
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioFormat."])
                    self.stopRecording()
                    return
                }

                do {
                    self.audioFile = try AVAudioFile(forWriting: outputURL, settings: avFormat.settings)
                } catch {
                    Logger.error("[MainActor Task] Failed to create AVAudioFile", error: error, category: .audio)
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
                    Logger.error("[MainActor Task] Failed to create PCM buffer from sample buffer.", category: .audio)
                    return
                }

                try audioFile.write(from: pcmBuffer)

            } catch {
                Logger.error("[MainActor Task] Failed to process or write audio buffer", error: error, category: .audio)
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
            Logger.error("[createPCMBufferFrom] Failed to get source ASBD from sampleBuffer.", category: .audio)
            return nil
        }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            Logger.error("[createPCMBufferFrom] Failed to create AVAudioPCMBuffer with target format.", category: .audio)
            return nil
        }
        pcmBuffer.frameLength = frameCount

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            Logger.error("[createPCMBufferFrom] Failed to get data buffer (CMBlockBuffer).", category: .audio)
            return nil
        }

        var dataLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>? = nil

        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &dataLength,
            totalLengthOut: nil,
            dataPointerOut: &dataPointer
        )

        if status != kCMBlockBufferNoErr {
            Logger.error("[createPCMBufferFrom] Failed to get data pointer from block buffer: \(status).", category: .audio)
            return nil
        }

        guard let sourceDataPtr = dataPointer else {
            Logger.error("[createPCMBufferFrom] dataPointer is nil after CMBlockBufferGetDataPointer.", category: .audio)
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
                        Logger.warning("[createPCMBufferFrom] Read out of bounds or dataLength insufficient. channel=\(channel), frame=\(frame), offset=\(finalSourceSampleMemoryOffset), dataLength=\(dataLength). Filling with 0.", category: .audio)
                        destinationChannelBuffer[frame] = 0.0
                    }
                }
            }
        } else if format.commonFormat == .pcmFormatInt16, let targetInt16ChannelData = pcmBuffer.int16ChannelData {
            Logger.warning("[createPCMBufferFrom] Using int16ChannelData. CAUTION: Untested/Unexpected path for float source.", category: .audio)
            let samplesPerChannel = Int(frameCount)
            for channel in 0..<targetChannelCount {
                let destinationChannelBuffer = targetInt16ChannelData[channel]
                for frame in 0..<samplesPerChannel {
                    destinationChannelBuffer[frame] = 0
                }
            }
        } else {
            Logger.error("[createPCMBufferFrom] PCM buffer data pointers (float/int16) are nil or format is unsupported for direct copy. Target Format: \(format.commonFormat).", category: .audio)
            return nil
        }

        return pcmBuffer
    }

    // MARK: - SCStreamDelegate

    nonisolated
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            Logger.error("Stream stopped with error", error: error, category: .audio)
            self.error = error
            self.stream = nil
            self.audioFile = nil
            self.isRecording = false
        }
    }

    // Calculate and update audio levels from the sample buffer
    private nonisolated func updateAudioLevels(from sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        var dataLength: size_t = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &dataLength,
            totalLengthOut: nil,
            dataPointerOut: &dataPointer
        )

        if status != kCMBlockBufferNoErr || dataPointer == nil {
            return
        }

        // Get the audio data to calculate RMS power
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
            return
        }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        if frameCount == 0 { return }
        let channelCount = Int(asbd.pointee.mChannelsPerFrame)
        if channelCount == 0 { return }

        var sumSquares: Float = 0.0

        // Assuming audio data is 32-bit float
        if (asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0 && asbd.pointee.mBitsPerChannel == 32 {
            let floatDataPointer = UnsafeRawPointer(dataPointer!)!.assumingMemoryBound(to: Float.self)
            let sampleCount = frameCount * channelCount

            if dataLength < sampleCount * MemoryLayout<Float>.size {
                return
            }

            let sampleStep = max(1, sampleCount / 1024)
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
                if self.audioLevels.count == 10 {
                    self.audioLevels.removeFirst()
                }
                self.audioLevels.append(0.0)
            }
            return
        }

        let rms = sqrtf(sumSquares)
        let powerInDb = 20.0 * log10(Double(rms + 1e-10))
        let normalizedLevel = Float(min(1.0, max(0.0, (powerInDb + 50) / 50)))

        Task { @MainActor in
            if self.audioLevels.count == 10 {
                self.audioLevels.removeFirst()
            }
            self.audioLevels.append(normalizedLevel)
        }
    }
}
