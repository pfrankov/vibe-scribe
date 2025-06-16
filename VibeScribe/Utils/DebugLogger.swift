import Foundation
import os.log

/// Debug logger specifically for development - can be easily disabled for production builds
struct DebugLogger {
    
    /// Controls whether debug logging is enabled
    /// Set to false for production builds to improve performance
    private static let isDebugEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
    
    /// Log debug information only in debug builds
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func debug(
        _ message: String,
        category: Logger.LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isDebugEnabled else { return }
        Logger.debug(message, category: category.osLog, file: file, function: function, line: line)
    }
    
    /// Log verbose transcription updates only in debug builds
    /// This is for detailed SSE streaming logs that would be too noisy in production
    static func transcriptionVerbose(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isDebugEnabled else { return }
        Logger.debug("🔄 \(message)", category: .transcription, file: file, function: function, line: line)
    }
    
    /// Log UI interactions only in debug builds
    static func ui(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isDebugEnabled else { return }
        Logger.debug("🎯 \(message)", category: .ui, file: file, function: function, line: line)
    }
}

// MARK: - Extensions

extension Logger {
    enum LogCategory {
        case general
        case audio
        case transcription
        case ui
        case network
        case data
        case security
        
        var osLog: OSLog {
            switch self {
            case .general: return Logger.general
            case .audio: return Logger.audio
            case .transcription: return Logger.transcription
            case .ui: return Logger.ui
            case .network: return Logger.network
            case .data: return Logger.data
            case .security: return Logger.security
            }
        }
    }
} 