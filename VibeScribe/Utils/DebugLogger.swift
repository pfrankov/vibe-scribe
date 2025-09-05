import Foundation
import os.log

/// Lightweight facade that keeps debug-only helpers while delegating to the unified Logger.
/// Intentionally minimal to reduce cognitive load while preserving existing call sites.
struct DebugLogger {
    /// Debug-only trace. No-op in Release.
    static func debug(
        _ message: String,
        category: OSLog = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.debug(message, category: category, file: file, function: function, line: line)
    }

    /// Verbose transcription trace for streaming scenarios. No-op in Release.
    static func transcriptionVerbose(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.debug("🔄 \(message)", category: .transcription, file: file, function: function, line: line)
    }

    /// UI interaction trace. No-op in Release.
    static func ui(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.debug("🎯 \(message)", category: .ui, file: file, function: function, line: line)
    }
}