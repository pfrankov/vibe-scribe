import Foundation

@main
struct InvalidChunkSizeProbe {
    static func main() {
        let size = Int(CommandLine.arguments[1])!
        FileHandle.standardOutput.write(Data("ENTER_CHUNKER\n".utf8))
        let chunks = TextChunker.chunkText("example", maxChunkSize: size)
        guard chunks.isEmpty else {
            FileHandle.standardError.write(Data("Invalid chunk size returned content\n".utf8))
            exit(1)
        }
        print("PASS: invalid chunk size returns no chunks")
    }
}
