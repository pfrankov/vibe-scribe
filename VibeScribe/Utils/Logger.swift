import Foundation
import os.log

/// Centralized logging utility for VibeScribe
/// Provides structured logging with different levels and categories
struct Logger {
    
    // MARK: - Log Categories
    
    /// Audio recording and playback operations
    static let audio = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "Audio")
    
    /// Transcription operations
    static let transcription = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "transcription")
    
    /// User interface operations
    static let ui = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "UI")
    
    /// Network operations
    static let network = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "Network")
    
    /// Data persistence operations
    static let data = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "Data")
    
    /// General application operations
    static let general = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "General")
    
    /// Security-related operations
    static let security = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "Security")
    
    /// LLM API interactions and prompt logging
    static let llm = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "VibeScribe", category: "LLM")
    
    // MARK: - Logging Methods
    
    /// Log debug information
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func debug(
        _ message: String,
        category: OSLog = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        os_log(.debug, log: category, "%{public}@:%{public}@:%d - %{public}@", 
               fileName, function, line, message)
        #endif
    }
    
    /// Log general information
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func info(
        _ message: String,
        category: OSLog = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        os_log(.info, log: category, "%{public}@:%{public}@:%d - %{public}@", 
               fileName, function, line, message)
    }
    
    /// Log warnings
    /// - Parameters:
    ///   - message: The message to log
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func warning(
        _ message: String,
        category: OSLog = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        os_log(.default, log: category, "⚠️ %{public}@:%{public}@:%d - %{public}@", 
               fileName, function, line, message)
    }
    
    /// Log errors
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error object for additional context
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func error(
        _ message: String,
        error: Error? = nil,
        category: OSLog = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let errorDescription = error?.localizedDescription ?? ""
        let fullMessage = errorDescription.isEmpty ? message : "\(message) - \(errorDescription)"
        
        os_log(.error, log: category, "❌ %{public}@:%{public}@:%d - %{public}@", 
               fileName, function, line, fullMessage)
    }
    
    /// Log critical errors that may cause app failure
    /// - Parameters:
    ///   - message: The message to log
    ///   - error: Optional error object for additional context
    ///   - category: The log category (defaults to general)
    ///   - file: The file name (automatically filled)
    ///   - function: The function name (automatically filled)
    ///   - line: The line number (automatically filled)
    static func critical(
        _ message: String,
        error: Error? = nil,
        category: OSLog = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let errorDescription = error?.localizedDescription ?? ""
        let fullMessage = errorDescription.isEmpty ? message : "\(message) - \(errorDescription)"
        
        os_log(.fault, log: category, "🚨 %{public}@:%{public}@:%d - %{public}@", 
               fileName, function, line, fullMessage)
    }
}

// MARK: - Extensions

extension OSLog {
    /// Convenience property for accessing the general log category
    static let general = Logger.general
    static let audio = Logger.audio
    static let transcription = Logger.transcription
    static let ui = Logger.ui
    static let network = Logger.network
    static let data = Logger.data
    static let security = Logger.security
    static let llm = Logger.llm
} 
