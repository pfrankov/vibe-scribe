import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import Darwin

@MainActor
class SystemAudioRecorderManager: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var error: Error?
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10)

    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var didLogFirstFormat = false
    
    // Aggregated level logging (system audio)
    private var levelLogMinDb: Double = 100
    private var levelLogMaxDb: Double = -100
    private var levelLogSumDb: Double = 0
    private var levelLogCount: Int = 0
    private var levelLogLastTime: CFAbsoluteTime = 0

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

        // Update audio levels (visualization). Writing to file is still gated on MainActor below.
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
        let streamDesc = asbdPtr.pointee

        let frameCount = AVAudioFrameCount(numSamples)

        Task { @MainActor in
            guard self.isRecording && !self.isPaused else {
                return
            }

            if self.audioFile == nil {
                guard let outputURL = self.outputURL else {
                    Logger.error("[MainActor Task] Output URL is nil during init.", category: .audio)
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Output URL not set."])
                    self.stopRecording()
                    return
                }

                // Create a mono float32 target format to downmix into
                let sampleRate = Double(streamDesc.mSampleRate)
                guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
                    Logger.error("[MainActor Task] Failed to create mono AVAudioFormat.", category: .audio)
                    self.error = NSError(domain: "SystemAudioRecorderManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create mono AVAudioFormat."])
                    self.stopRecording()
                    return
                }

                do {
                    self.audioFile = try AVAudioFile(forWriting: outputURL, settings: monoFormat.settings)
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
                guard let monoBuffer = createMonoFloatBuffer(from: sampleBuffer,
                                                             frameCount: frameCount,
                                                             sampleRate: audioFile.processingFormat.sampleRate) else {
                    Logger.error("[MainActor Task] Failed to create mono PCM buffer from sample buffer.", category: .audio)
                    return
                }

                try audioFile.write(from: monoBuffer)

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

    // Create a mono Float32 AVAudioPCMBuffer from a CMSampleBuffer (handles float32 and int16 sources)
    private nonisolated func createMonoFloatBuffer(from sampleBuffer: CMSampleBuffer,
                                                   frameCount: AVAudioFrameCount,
                                                   sampleRate: Double) -> AVAudioPCMBuffer? {
        var neededSize = 0
        let flags = UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment)
        var blockBuffer: CMBlockBuffer?
        // Query size
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: flags,
            blockBufferOut: &blockBuffer
        ) == noErr, neededSize > 0 else { return nil }

        // Allocate ABL
        let ablRaw = UnsafeMutableRawPointer.allocate(byteCount: neededSize, alignment: 16)
        defer { ablRaw.deallocate() }
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablRaw.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: neededSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: flags,
            blockBufferOut: &blockBuffer
        ) == noErr else { return nil }
        let ablPtr = ablRaw.assumingMemoryBound(to: AudioBufferList.self)
        let audioBufferList = UnsafeMutableAudioBufferListPointer(ablPtr)

        // Target mono Float32 format
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return nil }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: frameCount) else { return nil }
        pcm.frameLength = frameCount
        guard let out = pcm.floatChannelData?[0] else { return nil }

        // Determine source numeric format from the first buffer
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return nil }
        let bitsPerChannel = Int(asbd.mBitsPerChannel)

        // Clear output
        let framesI = Int(frameCount)
        for i in 0..<framesI { out[i] = 0 }
        var contributingChannels = 0

        // Mix down all channels from all buffers
        for buffer in audioBufferList {
            guard let mData = buffer.mData else { continue }
            let channelsInBuffer = Int(buffer.mNumberChannels)
            if channelsInBuffer == 0 { continue }
            let sampleCount = Int(buffer.mDataByteSize) / max(1, bitsPerChannel/8)
            if sampleCount == 0 { continue }

            if bitsPerChannel == 32 {
                let ptr = mData.assumingMemoryBound(to: Float.self)
                if channelsInBuffer == 1 {
                    for i in 0..<min(framesI, sampleCount) { out[i] += ptr[i] }
                } else {
                    for i in 0..<min(framesI, sampleCount/channelsInBuffer) {
                        var sum: Float = 0
                        let base = i * channelsInBuffer
                        for ch in 0..<channelsInBuffer { sum += ptr[base + ch] }
                        out[i] += sum / Float(channelsInBuffer)
                    }
                }
                contributingChannels += channelsInBuffer
            } else if bitsPerChannel == 16 {
                let ptr = mData.assumingMemoryBound(to: Int16.self)
                let scale = 1.0 / Float(Int16.max)
                if channelsInBuffer == 1 {
                    for i in 0..<min(framesI, sampleCount) { out[i] += Float(ptr[i]) * scale }
                } else {
                    for i in 0..<min(framesI, sampleCount/channelsInBuffer) {
                        var sum: Float = 0
                        let base = i * channelsInBuffer
                        for ch in 0..<channelsInBuffer { sum += Float(ptr[base + ch]) * scale }
                        out[i] += sum / Float(channelsInBuffer)
                    }
                }
                contributingChannels += channelsInBuffer
            }
        }

        // If multiple buffers contributed, average by buffer count to avoid over-amplification
        if contributingChannels > 1 {
            let scale = 1.0 / Float(contributingChannels)
            for i in 0..<framesI { out[i] *= scale }
        }

        return pcm
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

    // Calculate and update audio levels from CMSampleBuffer using AudioBufferList.
    // This path is robust for ScreenCaptureKit audio and yields consistent levels.
    private nonisolated func updateAudioLevels(from sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }
        let asbd = asbdPtr.pointee
        let srConst = asbd.mSampleRate
        let chConst = Int(asbd.mChannelsPerFrame)
        let bitsConst = Int(asbd.mBitsPerChannel)
        let flagsConst = asbd.mFormatFlags
        Task { @MainActor in
            if !self.didLogFirstFormat {
                Logger.info(String(format: "System ASBD — sr: %.0f, ch: %d, bits: %d, flags: 0x%X", srConst, chConst, bitsConst, flagsConst), category: .audio)
                self.didLogFirstFormat = true
            }
        }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        if frames == 0 { return }

        // Query required size for AudioBufferList
        var neededSize = 0
        let flags = UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment)
        let queryStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: flags,
            blockBufferOut: nil
        )
        if queryStatus != noErr || neededSize <= 0 { return }

        // Allocate aligned memory for AudioBufferList
        let ablRaw = UnsafeMutableRawPointer.allocate(byteCount: neededSize, alignment: 16)
        defer { ablRaw.deallocate() }
        var blockBuffer: CMBlockBuffer?
        let fetchStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablRaw.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: neededSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: flags,
            blockBufferOut: &blockBuffer
        )
        if fetchStatus != noErr { return }

        let ablPtr = ablRaw.assumingMemoryBound(to: AudioBufferList.self)
        let audioBufferList = UnsafeMutableAudioBufferListPointer(ablPtr)
        let bufferCountConst = audioBufferList.count
        let channelCountConst = Int(asbd.mChannelsPerFrame)

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bitsPerChannel = Int(asbd.mBitsPerChannel)
        let bytesPerSample = max(1, bitsPerChannel / 8)

        var sumSquares: Double = 0
        var counted: Int = 0

        for buffer in audioBufferList {
            guard let mData = buffer.mData else { continue }
            let byteSize = Int(buffer.mDataByteSize)
            let sampleCount = byteSize / bytesPerSample
            if sampleCount == 0 { continue }
            let step = max(1, sampleCount / 1024) // subsample for efficiency

            if isFloat && bitsPerChannel == 32 {
                let ptr = mData.assumingMemoryBound(to: Float.self)
                for i in stride(from: 0, to: sampleCount, by: step) {
                    let v = Double(ptr[i])
                    sumSquares += v * v
                    counted += 1
                }
            } else if bitsPerChannel == 16 {
                let ptr = mData.assumingMemoryBound(to: Int16.self)
                let scale = 1.0 / Double(Int16.max)
                for i in stride(from: 0, to: sampleCount, by: step) {
                    let v = Double(ptr[i]) * scale
                    sumSquares += v * v
                    counted += 1
                }
            }
        }

        if counted == 0 { return }
        let meanSquare = sumSquares / Double(counted)
        let rms = sqrt(meanSquare)
        let powerDb = 20.0 * log10(rms + 1e-12)
        
        // Unified visual curve (matches mic path)
        let minDb: Double = -80
        let clipped = max(minDb, powerDb)
        let normalizedDb = (clipped - minDb) / (-minDb) // 0..1
        let level = max(0.0, min(1.0, pow(normalizedDb, 1.1)))

        #if DEBUG
        Task { @MainActor in
            if self.audioLevels.count == 10 { self.audioLevels.removeFirst() }
            self.audioLevels.append(Float(level))

            // Aggregate and log every 0.5s for diagnostics
            self.levelLogMinDb = min(self.levelLogMinDb, powerDb)
            self.levelLogMaxDb = max(self.levelLogMaxDb, powerDb)
            self.levelLogSumDb += powerDb
            self.levelLogCount += 1
            let now = CFAbsoluteTimeGetCurrent()
            if now - self.levelLogLastTime > 1.0, self.levelLogCount > 0 {
                let avg = self.levelLogSumDb / Double(self.levelLogCount)
                Logger.debug(String(format: "System level dB min/avg/max: %.1f / %.1f / %.1f | buffers:%d ch:%d | active:%@ paused:%@", self.levelLogMinDb, avg, self.levelLogMaxDb, bufferCountConst, channelCountConst, self.isRecording.description, self.isPaused.description), category: .audio)
                self.levelLogMinDb = 100
                self.levelLogMaxDb = -100
                self.levelLogSumDb = 0
                self.levelLogCount = 0
                self.levelLogLastTime = now
            }
        }
        #else
        Task { @MainActor in
            if self.audioLevels.count == 10 { self.audioLevels.removeFirst() }
            self.audioLevels.append(Float(level))
        }
        #endif
    }
}

// MARK: - Pause/Resume
extension SystemAudioRecorderManager {
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
    }
}
