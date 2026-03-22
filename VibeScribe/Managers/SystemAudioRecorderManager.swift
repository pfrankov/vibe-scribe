import Foundation
import Combine

extension SystemAudioTapRecorder: @unchecked Sendable {}

@MainActor
final class SystemAudioRecorderManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var isPaused = false
    @Published var error: Error?
    @Published var audioLevels: [Float] = Array(repeating: 0.0, count: 10)

    private let recorderQueue = DispatchQueue(label: "com.vibescribe.systemAudioRecorder")
    private let idleLevels = Array(repeating: Float(0.0), count: 10)

    private var recorder: SystemAudioTapRecorder?
    private var meterTimer: Timer?
    private var sessionID = UUID()

    func startRecording(outputURL: URL) {
        Logger.info("Attempting to start system audio recording", category: .audio)

        guard recorder == nil else {
            Logger.warning("System audio recorder is already active", category: .audio)
            return
        }

        error = nil
        isPaused = false
        audioLevels = idleLevels

        let directory = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.error("Failed to create directory for system audio recording", error: error, category: .audio)
            self.error = error
            return
        }

        let recorder = SystemAudioTapRecorder()
        let sessionID = UUID()
        let excludedBundleID = Bundle.main.bundleIdentifier

        self.recorder = recorder
        self.sessionID = sessionID

        recorderQueue.async {
            do {
                try recorder.prepareRecording(at: outputURL, excludedBundleID: excludedBundleID)
                try recorder.startRecording()

                DispatchQueue.main.async {
                    guard self.sessionID == sessionID, self.recorder === recorder else { return }

                    self.isRecording = true
                    self.isPaused = false
                    self.startMeterPolling()
                    Logger.info("Started recording system audio via Core Audio tap", category: .audio)
                }
            } catch {
                recorder.invalidate()

                DispatchQueue.main.async {
                    guard self.sessionID == sessionID, self.recorder === recorder else { return }

                    self.recorder = nil
                    self.isRecording = false
                    self.isPaused = false
                    self.audioLevels = self.idleLevels
                    self.deleteFileIfPresent(at: outputURL)
                    self.error = error
                    Logger.error("Failed to start system audio recording", error: error, category: .audio)
                }
            }
        }
    }

    func stopRecording() {
        Logger.info("Stopping system audio recording", category: .audio)
        tearDownRecorder(deleteOutputFile: false)
    }

    func pauseRecording() {
        guard isRecording, !isPaused, let recorder else { return }

        recorder.isPaused = true
        isPaused = true
        appendMeterLevel(0.0)
    }

    func resumeRecording() {
        guard isRecording, isPaused, let recorder else { return }

        recorder.isPaused = false
        isPaused = false
    }

    private func tearDownRecorder(deleteOutputFile: Bool) {
        let retiringRecorder = recorder
        let retiringOutputURL = recorder?.outputURL

        sessionID = UUID()
        recorder = nil
        stopMeterPolling()
        isRecording = false
        isPaused = false
        audioLevels = idleLevels

        guard let retiringRecorder else {
            if deleteOutputFile {
                deleteFileIfPresent(at: retiringOutputURL)
            }
            return
        }

        recorderQueue.sync {
            retiringRecorder.invalidate()
        }

        if deleteOutputFile {
            deleteFileIfPresent(at: retiringOutputURL)
        }
    }

    private func startMeterPolling() {
        stopMeterPolling()

        meterTimer = Timer.scheduledTimer(
            timeInterval: 0.05,
            target: self,
            selector: #selector(handleMeterTimerTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(meterTimer!, forMode: .common)
    }

    private func stopMeterPolling() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    @objc
    private func handleMeterTimerTick() {
        guard let recorder else {
            stopMeterPolling()
            return
        }

        let level = isPaused ? 0.0 : recorder.meterLevel
        appendMeterLevel(level)
    }

    private func appendMeterLevel(_ level: Float) {
        let normalized = min(1.0, max(0.0, level))
        if audioLevels.count == idleLevels.count {
            audioLevels.removeFirst()
        }
        audioLevels.append(normalized)
    }

    private func deleteFileIfPresent(at url: URL?) {
        guard let url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try FileManager.default.removeItem(at: url)
            Logger.info("Removed unused system audio file: \(url.lastPathComponent)", category: .audio)
        } catch {
            Logger.warning("Failed to remove unused system audio file: \(error.localizedDescription)", category: .audio)
        }
    }
}
