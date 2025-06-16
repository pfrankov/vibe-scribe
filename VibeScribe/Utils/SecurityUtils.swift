import Foundation
import Security

/// Utility class for handling sensitive data like API keys securely
struct SecurityUtils {
    
    private static let keychainService = "com.vibescribe.apikeys"
    
    // MARK: - Keychain Operations
    
    /// Store API key securely in Keychain
    static func storeAPIKey(_ key: String, for identifier: String) -> Bool {
        guard !key.isEmpty else { return false }
        
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Retrieve API key securely from Keychain
    static func retrieveAPIKey(for identifier: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    /// Delete API key from Keychain
    static func deleteAPIKey(for identifier: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: identifier
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Input Validation
    
    /// Sanitize API key input to prevent injection attacks
    static func sanitizeAPIKey(_ key: String) -> String {
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "")
    }
    
    /// Validate URL to prevent malicious redirects
    static func validateURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        
        // Only allow HTTPS for API endpoints
        return scheme == "https" && url.host != nil
    }
    
    /// Mask API key for logging purposes
    static func maskAPIKey(_ key: String) -> String {
        guard key.count > 8 else { return "***" }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)***\(suffix)"
    }
}

// MARK: - Constants

extension SecurityUtils {
    static let whisperAPIKeyIdentifier = "whisper_api_key"
    static let openAIAPIKeyIdentifier = "openai_api_key"
} 