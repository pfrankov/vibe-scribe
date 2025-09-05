import Foundation

/// Utility class for handling sensitive data like API keys securely
struct SecurityUtils {
    
    // MARK: - Input Validation
    
    /// Sanitize API key input to prevent injection attacks
    static func sanitizeAPIKey(_ key: String) -> String {
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }
    
    
    /// Mask API key for logging purposes
    static func maskAPIKey(_ key: String) -> String {
        guard key.count > 8 else { return "***" }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)***\(suffix)"
    }
}

// (Intentionally no constants: previously unused identifiers removed)