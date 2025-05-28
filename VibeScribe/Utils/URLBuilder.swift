//
//  URLBuilder.swift
//  VibeScribe
//
//  Created by System on 14.04.2025.
//

import Foundation

/// Utility for building OpenAI-compatible API URLs
struct APIURLBuilder {
    
    /// Build URL for OpenAI-compatible endpoints
    /// - Parameters:
    ///   - baseURL: Base URL (e.g., "https://api.openai.com/v1/" or "https://api.openai.com")
    ///   - endpoint: Endpoint path (e.g., "models", "chat/completions", "audio/transcriptions")
    /// - Returns: Complete URL or nil if invalid
    static func buildURL(baseURL: String, endpoint: String) -> URL? {
        guard !baseURL.isEmpty, !endpoint.isEmpty else { return nil }
        
        var normalizedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure base URL ends with /v1/
        if !normalizedBase.hasSuffix("/v1/") && !normalizedBase.hasSuffix("/v1") {
            if normalizedBase.hasSuffix("/") {
                normalizedBase += "v1/"
            } else {
                normalizedBase += "/v1/"
            }
        } else if normalizedBase.hasSuffix("/v1") {
            normalizedBase += "/"
        }
        
        // Remove leading slash from endpoint if present
        let normalizedEndpoint = endpoint.hasPrefix("/") ? String(endpoint.dropFirst()) : endpoint
        
        return URL(string: normalizedBase + normalizedEndpoint)
    }
    
    /// Validate if base URL is properly formatted
    static func isValidBaseURL(_ baseURL: String) -> Bool {
        guard !baseURL.isEmpty else { return false }
        guard let url = URL(string: baseURL) else { return false }
        return url.scheme != nil && url.host != nil
    }
} 