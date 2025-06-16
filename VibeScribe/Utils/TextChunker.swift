import Foundation

/// Advanced text chunking utility that respects natural boundaries
/// Splits text in order of preference: paragraphs, sentences, then characters
struct TextChunker {
    
    /// Chunk text intelligently based on natural boundaries
    /// - Parameters:
    ///   - text: The text to chunk
    ///   - maxChunkSize: Maximum size per chunk in characters
    ///   - forceChunking: If false, returns single chunk if text fits within maxChunkSize
    /// - Returns: Array of text chunks
    static func chunkText(_ text: String, maxChunkSize: Int, forceChunking: Bool = false) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Return single chunk if text is small enough and we're not forcing chunking
        if !forceChunking && trimmedText.count <= maxChunkSize {
            return [trimmedText]
        }
        
        // Try chunking by paragraphs first
        if let paragraphChunks = tryChunkByParagraphs(trimmedText, maxChunkSize: maxChunkSize) {
            return paragraphChunks
        }
        
        // Fall back to sentence-based chunking
        if let sentenceChunks = tryChunkBySentences(trimmedText, maxChunkSize: maxChunkSize) {
            return sentenceChunks
        }
        
        // Last resort: chunk by characters while trying to preserve word boundaries
        return chunkByWordsWithFallback(trimmedText, maxChunkSize: maxChunkSize)
    }
    
    // MARK: - Private Methods
    
    /// Try to chunk by paragraphs (double newlines)
    private static func tryChunkByParagraphs(_ text: String, maxChunkSize: Int) -> [String]? {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // If we only have one paragraph or any paragraph is too large, this method fails
        if paragraphs.count <= 1 {
            return nil
        }
        
        for paragraph in paragraphs {
            if paragraph.count > maxChunkSize {
                return nil // Can't use paragraph chunking if any paragraph is too big
            }
        }
        
        // Combine paragraphs until we reach the size limit
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentSize = 0
        
        for paragraph in paragraphs {
            let paragraphSize = paragraph.count
            let separatorSize = currentChunk.isEmpty ? 0 : 2 // "\n\n"
            
            if currentSize + separatorSize + paragraphSize <= maxChunkSize {
                currentChunk.append(paragraph)
                currentSize += separatorSize + paragraphSize
            } else {
                // Finalize current chunk
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.joined(separator: "\n\n"))
                }
                // Start new chunk
                currentChunk = [paragraph]
                currentSize = paragraphSize
            }
        }
        
        // Add the last chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: "\n\n"))
        }
        
        return chunks.isEmpty ? nil : chunks
    }
    
    /// Try to chunk by sentences (periods, exclamation marks, question marks)
    private static func tryChunkBySentences(_ text: String, maxChunkSize: Int) -> [String]? {
        // Split by sentence endings, but keep the punctuation
        let sentences = splitBySentences(text)
        
        if sentences.count <= 1 {
            return nil
        }
        
        // Check if any single sentence is too large
        for sentence in sentences {
            if sentence.count > maxChunkSize {
                return nil // Can't use sentence chunking if any sentence is too big
            }
        }
        
        // Combine sentences until we reach the size limit
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentSize = 0
        
        for sentence in sentences {
            let sentenceSize = sentence.count
            let separatorSize = currentChunk.isEmpty ? 0 : 1 // space between sentences
            
            if currentSize + separatorSize + sentenceSize <= maxChunkSize {
                currentChunk.append(sentence)
                currentSize += separatorSize + sentenceSize
            } else {
                // Finalize current chunk
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.joined(separator: " "))
                }
                // Start new chunk
                currentChunk = [sentence]
                currentSize = sentenceSize
            }
        }
        
        // Add the last chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        
        return chunks.isEmpty ? nil : chunks
    }
    
    /// Split text by sentence boundaries while preserving punctuation
    private static func splitBySentences(_ text: String) -> [String] {
        // Use regex to split by sentence endings but keep the punctuation
        let pattern = "(?<=[.!?])\\s+"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: text.utf16.count)
            let sentences = regex.split(text, range: range)
            
            return sentences
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            // Fallback to simple splitting if regex fails
            return text.components(separatedBy: ". ")
                .flatMap { $0.components(separatedBy: "! ") }
                .flatMap { $0.components(separatedBy: "? ") }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
    
    /// Last resort chunking by words with character limit fallback
    private static func chunkByWordsWithFallback(_ text: String, maxChunkSize: Int) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        if words.isEmpty {
            return []
        }
        
        var chunks: [String] = []
        var currentChunk: [String] = []
        var currentSize = 0
        
        for word in words {
            let wordSize = word.count
            let separatorSize = currentChunk.isEmpty ? 0 : 1 // space between words
            
            // If even a single word is too large, we need to split it by characters
            if wordSize > maxChunkSize {
                // Finalize current chunk if any
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.joined(separator: " "))
                    currentChunk = []
                    currentSize = 0
                }
                
                // Split the oversized word by characters
                let characterChunks = splitWordByCharacters(word, maxChunkSize: maxChunkSize)
                chunks.append(contentsOf: characterChunks)
                continue
            }
            
            if currentSize + separatorSize + wordSize <= maxChunkSize {
                currentChunk.append(word)
                currentSize += separatorSize + wordSize
            } else {
                // Finalize current chunk
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.joined(separator: " "))
                }
                // Start new chunk
                currentChunk = [word]
                currentSize = wordSize
            }
        }
        
        // Add the last chunk
        if !currentChunk.isEmpty {
            chunks.append(currentChunk.joined(separator: " "))
        }
        
        return chunks
    }
    
    /// Split a word that's too large by characters
    private static func splitWordByCharacters(_ word: String, maxChunkSize: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = word.startIndex
        
        while currentIndex < word.endIndex {
            let endIndex = word.index(currentIndex, offsetBy: min(maxChunkSize, word.distance(from: currentIndex, to: word.endIndex)))
            let chunk = String(word[currentIndex..<endIndex])
            chunks.append(chunk)
            currentIndex = endIndex
        }
        
        return chunks
    }
}

// MARK: - NSRegularExpression Extension

private extension NSRegularExpression {
    func split(_ string: String, range: NSRange) -> [String] {
        let matches = self.matches(in: string, options: [], range: range)
        var result: [String] = []
        var lastEnd = 0
        
        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastEnd {
                let substringRange = NSRange(location: lastEnd, length: matchRange.location - lastEnd)
                if let range = Range(substringRange, in: string) {
                    result.append(String(string[range]))
                }
            }
            lastEnd = matchRange.location + matchRange.length
        }
        
        // Add the remaining part
        if lastEnd < string.count {
            let substringRange = NSRange(location: lastEnd, length: string.count - lastEnd)
            if let range = Range(substringRange, in: string) {
                result.append(String(string[range]))
            }
        }
        
        return result
    }
} 