//
//  AudioFileImportManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import Foundation
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Import Errors

enum AudioFileImportError: LocalizedError {
    case fileNotFound(String)
    case unsupportedFormat(String)
    case invalidAudioFile(String)
    case conversionFailed(String)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let message):
            return "File not found: \(message)"
        case .unsupportedFormat(let message):
            return "Unsupported format: \(message)"
        case .invalidAudioFile(let message):
            return "Invalid audio file: \(message)"
        case .conversionFailed(let message):
            return "Conversion failed: \(message)"
        case .saveFailed(let message):
            return "Save failed: \(message)"
        }
    }
}

@MainActor
class AudioFileImportManager: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: String = ""
    @Published var error: Error? = nil
    
    // Private task for cancellation support
    private var importTask: Task<Void, Never>?
    
    // Supported audio file types - made private and with computed public access
    private static let audioFileExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "ogg", "flac", "wma", "mp4", "mov"
    ]
    
    private static let audioUTTypes: Set<String> = [
        "public.mp3", "public.audio", "public.audiovisual-content",
        "com.microsoft.waveform-audio", "public.aiff-audio",
        "public.mpeg-4-audio", "public.ac3-audio"
    ]
    
    /// Supported audio file extensions
    static var supportedAudioTypes: [String] {
        Array(audioFileExtensions).sorted()
    }
    
    /// Supported UTI types for audio files
    static var supportedUTTypes: [String] {
        Array(audioUTTypes).sorted()
    }
    
    /// Supported Uniform Type Identifiers for file import panels
    static var supportedContentTypes: [UTType] {
        var types: Set<UTType> = [.audio]
        
        for ext in audioFileExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.insert(type)
            }
        }
        
        return Array(types)
    }
    
    deinit {
        importTask?.cancel()
    }
    
    /// Imports audio files from drag-and-drop
    /// - Parameters:
    ///   - urls: Array of URLs to import
    ///   - modelContext: SwiftData model context for saving records
    func importAudioFiles(urls: [URL], modelContext: ModelContext) {
        guard !isImporting else { 
            Logger.warning("Import already in progress, ignoring new request", category: .audio)
            return 
        }
        
        // Cancel any existing import task
        cancelImport()
        
        isImporting = true
        error = nil
        
        Logger.info("Starting import of \(urls.count) audio files", category: .audio)
        
        importTask = Task {
            var successCount = 0
            var failureCount = 0
            
            for (index, url) in urls.enumerated() {
                // Check for cancellation
                guard !Task.isCancelled else {
                    Logger.info("Import cancelled by user", category: .audio)
                    break
                }
                
                do {
                    try await importSingleFile(url: url, index: index + 1, total: urls.count, modelContext: modelContext)
                    successCount += 1
                } catch {
                    failureCount += 1
                    Logger.error("Failed to import file: \(url.lastPathComponent)", error: error, category: .audio)
                    await MainActor.run {
                        self.error = error
                    }
                }
            }
            
            await MainActor.run {
                self.isImporting = false
                self.importProgress = ""
                let totalProcessed = successCount + failureCount
                Logger.info("Import completed: \(successCount) successful, \(failureCount) failed out of \(totalProcessed) files", category: .audio)
            }
        }
    }
    
    /// Cancels the current import operation
    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        
        if isImporting {
            isImporting = false
            importProgress = ""
            Logger.info("Import operation cancelled", category: .audio)
        }
    }
    
    private func importSingleFile(url: URL, index: Int, total: Int, modelContext: ModelContext) async throws {
        await MainActor.run {
            importProgress = "Importing \(index)/\(total): \(url.lastPathComponent)"
        }
        
        Logger.info("Importing file \(index)/\(total): \(url.lastPathComponent)", category: .audio)
        
        // Validate file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioFileImportError.fileNotFound("File not found: \(url.lastPathComponent)")
        }
        
        // Check if file is actually an audio file
        guard isAudioFile(url: url) else {
            throw AudioFileImportError.unsupportedFormat("Unsupported file format: \(url.pathExtension)")
        }
        
        // Validate it's actually a valid audio file
        guard await AudioUtils.isValidAudioFile(url: url) else {
            throw AudioFileImportError.invalidAudioFile("File does not contain valid audio: \(url.lastPathComponent)")
        }
        
        // Get original filename with extension
        let originalName = url.lastPathComponent
        
        // Convert to standard format
        await MainActor.run {
            importProgress = "Converting \(index)/\(total): \(originalName)"
        }
        
        let convertedURL = try await convertToStandardFormat(url: url)
        
        // Get duration
        let duration = await AudioUtils.getAudioDuration(url: convertedURL)
        
        // Validate duration is reasonable
        guard duration > 0 else {
            throw AudioFileImportError.invalidAudioFile("Audio file has invalid duration: \(originalName)")
        }
        
        // Create record
        let record = Record(
            name: originalName,
            fileURL: convertedURL,
            duration: duration,
            includesSystemAudio: false // Imported files don't include system audio
        )
        
        try await MainActor.run {
            importProgress = "Saving \(index)/\(total): \(originalName)"
            
            modelContext.insert(record)
            
            do {
                try modelContext.save()
                Logger.info("Successfully imported and saved record: \(originalName)", category: .audio)
                
                // Notify about new record for UI updates
                NotificationCenter.default.post(
                    name: NSNotification.Name("NewRecordCreated"),
                    object: nil,
                    userInfo: ["recordId": record.id]
                )
                
                // The processing pipeline will start automatically when the record is viewed
                // thanks to the logic in RecordDetailView's onAppear and onReceive handlers
                
            } catch {
                Logger.error("Failed to save imported record: \(originalName)", error: error, category: .audio)
                throw AudioFileImportError.saveFailed("Failed to save record: \(error.localizedDescription)")
            }
        }
    }
    
    private func convertToStandardFormat(url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            AudioUtils.convertAudioToStandardFormat(inputURL: url) { result in
                switch result {
                case .success(let convertedURL):
                    continuation.resume(returning: convertedURL)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func isAudioFile(url: URL) -> Bool {
        let fileExtension = url.pathExtension.lowercased()
        return Self.audioFileExtensions.contains(fileExtension)
    }
    

}

// MARK: - Drag and Drop Support

extension AudioFileImportManager {
    /// Checks if any of the provided URLs are supported audio files
    static func containsSupportedAudioFiles(urls: [URL]) -> Bool {
        return urls.contains { url in
            let fileExtension = url.pathExtension.lowercased()
            return audioFileExtensions.contains(fileExtension)
        }
    }
    
    /// Filters URLs to only include supported audio files
    static func filterSupportedAudioFiles(urls: [URL]) -> [URL] {
        return urls.filter { url in
            let fileExtension = url.pathExtension.lowercased()
            return audioFileExtensions.contains(fileExtension)
        }
    }
    
    /// Validates multiple files concurrently
    static func validateAudioFiles(urls: [URL]) async -> [URL: Bool] {
        await withTaskGroup(of: (URL, Bool).self, returning: [URL: Bool].self) { group in
            for url in urls {
                group.addTask {
                    let isValid = await AudioUtils.isValidAudioFile(url: url)
                    return (url, isValid)
                }
            }
            
            var results: [URL: Bool] = [:]
            for await (url, isValid) in group {
                results[url] = isValid
            }
            return results
        }
    }
} 
