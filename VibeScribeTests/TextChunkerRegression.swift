import Foundation

@main
struct TextChunkerRegression {
    enum Failure: Error { case assertion(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.assertion(message) }
    }

    static func main() throws {
        let expectTruncation = CommandLine.arguments.contains("--expect-truncation")
        let fixtures: [(name: String, text: String, size: Int, historicallyTruncated: Bool)] = [
            ("ASCII", "A. B. C", 4, false),
            ("BMP", "猫. Б. 末", 4, false),
            ("emoji prefix", "😀. B. C", 4, true),
            ("combining prefix", "e\u{301}. B. C", 4, true),
            ("joined emoji prefix", "👩‍💻. B. Tail", 4, true),
            ("emoji tail", "A. B. 😀", 4, true),
            ("combining tail", "A. B. e\u{301}", 4, true),
            ("default-size transcript", "😀. " + String(repeating: "A. ", count: 10000) + "Tail", 25000, true)
        ]

        for fixture in fixtures {
            let chunks = TextChunker.chunkText(fixture.text, maxChunkSize: fixture.size)
            try require(!chunks.isEmpty, "\(fixture.name): no chunks returned")
            try require(chunks.allSatisfy { !$0.isEmpty && $0.count <= fixture.size }, "\(fixture.name): invalid chunk bounds")
            let reconstructed = chunks.joined(separator: " ")
            if expectTruncation && fixture.historicallyTruncated {
                try require(reconstructed != fixture.text, "\(fixture.name): historical truncation not reproduced")
                try require(reconstructed.utf16.count < fixture.text.utf16.count, "\(fixture.name): expected missing UTF-16 units")
                print("REPRODUCED: \(fixture.name) loses transcript characters")
            } else {
                try require(reconstructed == fixture.text, "\(fixture.name): chunks changed transcript content")
                try require(Array(reconstructed.utf8) == Array(fixture.text.utf8), "\(fixture.name): chunks changed Unicode representation")
                print("PASS: \(fixture.name) preserves exact content and chunk bounds")
            }
        }

        let short = "👩‍💻 e\u{301}"
        try require(TextChunker.chunkText(short, maxChunkSize: 100) == [short], "Short text changed")
        try require(TextChunker.chunkText("   ", maxChunkSize: 100) == [""], "Empty-text behavior changed")
        let paragraphs = TextChunker.chunkText("😀\n\n猫\n\nБ", maxChunkSize: 4)
        try require(paragraphs.joined(separator: "\n\n") == "😀\n\n猫\n\nБ", "Paragraph behavior changed")
        print("PASS: short, empty, and paragraph paths are unchanged")
    }
}
