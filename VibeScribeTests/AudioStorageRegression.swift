import AVFoundation
import Foundation

/// Exercises the real AVFoundation conversion and merge paths with generated tones.
@main
struct AudioStorageRegression {
    enum Failure: Error { case assertion(String) }

    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure.assertion(message) }
    }

    static func makeTone(at url: URL, frequency: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = buffer.frameCapacity
        for frame in 0..<Int(buffer.frameLength) {
            buffer.floatChannelData![0][frame] = Float(0.25 * sin(2 * Double.pi * frequency * Double(frame) / 44100))
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    static func convert(_ source: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            AudioUtils.convertAudioToStandardFormat(inputURL: source) {
                continuation.resume(with: $0)
            }
        }
    }

    static func merge(_ first: URL, _ second: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            AudioUtils.mergeAudioFiles(micURL: first, systemURL: second) {
                continuation.resume(with: $0)
            }
        }
    }

    static func checkPair(
        _ label: String,
        root: URL,
        expectCollision: Bool,
        first: () async throws -> URL,
        second: () async throws -> URL
    ) async throws {
        let firstURL = try await first()
        try require(firstURL.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL, "Output escaped fixture directory")
        let firstBytes = try Data(contentsOf: firstURL)
        try require(!firstBytes.isEmpty, "First export is empty")
        try require(await AudioUtils.getAudioDuration(url: firstURL) > 0, "First export has no valid duration")

        let secondURL = try await second()
        try require(secondURL.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL, "Output escaped fixture directory")
        let secondBytes = try Data(contentsOf: secondURL)
        try require(!secondBytes.isEmpty, "Second export is empty")
        try require(await AudioUtils.getAudioDuration(url: secondURL) > 0, "Second export has no valid duration")
        let preservedBytes = try Data(contentsOf: firstURL)

        if expectCollision {
            try require(firstURL == secondURL, "Baseline no longer reproduces the \(label) path collision")
            try require(firstBytes != preservedBytes, "Baseline did not overwrite \(label) audio")
            print("REPRODUCED: \(label) reused a path and changed earlier audio bytes")
        } else {
            try require(firstURL != secondURL, "\(label) reused an existing recording path")
            try require(firstBytes == preservedBytes, "\(label) changed earlier audio bytes")
            try require(firstBytes != secondBytes, "Synthetic inputs did not produce distinct audio")
            try FileManager.default.removeItem(at: secondURL)
            try require(try Data(contentsOf: firstURL) == firstBytes, "Removing the second \(label) output damaged the first")
            print("PASS: \(label) creates distinct outputs with valid media duration and preserves earlier audio")
        }
    }

    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let expectCollision = CommandLine.arguments.contains("--expect-collision")
        let first = root.appendingPathComponent("first.wav")
        let second = root.appendingPathComponent("second.wav")
        try makeTone(at: first, frequency: 440)
        try makeTone(at: second, frequency: 880)
        let firstSourceBytes = try Data(contentsOf: first)
        let secondSourceBytes = try Data(contentsOf: second)

        try await checkPair("import", root: root, expectCollision: expectCollision,
                            first: { try await convert(first) }, second: { try await convert(second) })
        try await checkPair("merge", root: root, expectCollision: expectCollision,
                            first: { try await merge(first, first) }, second: { try await merge(second, second) })
        try require(try Data(contentsOf: first) == firstSourceBytes, "First source was modified")
        try require(try Data(contentsOf: second) == secondSourceBytes, "Second source was modified")
        print("PASS: original synthetic WAV files are unchanged")
    }
}
