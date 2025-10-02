import SwiftUI

// Processing states for the audio pipeline
enum ProcessingState: Equatable {
    case idle
    case transcribing
    case summarizing
    case completed
    case error(String)
    case streamingTranscription([String]) // Array of SSE chunks for streaming display
    
    var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .transcribing:
            return "Transcribing..."
        case .streamingTranscription:
            return "Streaming transcription..."
        case .summarizing:
            return "Summarizing..."
        case .completed:
            return "Completed"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    var isProcessing: Bool {
        switch self {
        case .transcribing, .summarizing, .streamingTranscription:
            return true
        default:
            return false
        }
    }
    
    var isError: Bool {
        switch self {
        case .error:
            return true
        default:
            return false
        }
    }
    
    var isStreaming: Bool {
        switch self {
        case .streamingTranscription:
            return true
        default:
            return false
        }
    }
    
    var streamingChunks: [String] {
        switch self {
        case .streamingTranscription(let chunks):
            return chunks
        default:
            return []
        }
    }
    
    var progress: Double {
        switch self {
        case .idle:
            return 0.0
        case .transcribing, .streamingTranscription:
            return 0.5
        case .summarizing:
            return 0.8
        case .completed:
            return 1.0
        case .error:
            return 0.0
        }
    }
}

// Beautiful, minimalist processing progress view
struct ProcessingProgressView: View {
    let state: ProcessingState
    @State private var animatedProgress: Double = 0.0
    @State private var pulseAnimation: Bool = false
    
    private let primaryColor = Color.accentColor
    private let backgroundColor = Color(NSColor.controlBackgroundColor)
    private let secondaryTextColor = Color(NSColor.secondaryLabelColor)
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress Bar Container
            VStack(spacing: 12) {
                // Status Text
                HStack {
                    // Processing indicator dot
                    if state.isProcessing {
                        Circle()
                            .fill(primaryColor)
                            .frame(width: 8, height: 8)
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .opacity(pulseAnimation ? 0.7 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )
                            .onAppear {
                                pulseAnimation = true
                            }
                            .onDisappear {
                                pulseAnimation = false
                            }
                    } else if case .error = state {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 12))
                    } else if case .completed = state {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                    }
                    
                    Text(state.displayText)
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(colorForState(state))
                    
                    Spacer()
                    
                    // SSE indicator
                    if state.isStreaming {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .foregroundStyle(primaryColor.opacity(0.7))
                                .font(.system(size: 10))
                            Text("Live")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(primaryColor.opacity(0.8))
                        }
                    }
                }
                
                // Progress Bar
                if state.isProcessing || state.progress > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 3)
                                .fill(backgroundColor)
                                .frame(height: 6)
                            
                            // Progress fill
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [primaryColor, primaryColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geometry.size.width * animatedProgress,
                                    height: 6
                                )
                                .animation(
                                    .easeInOut(duration: 0.8),
                                    value: animatedProgress
                                )
                        }
                    }
                    .frame(height: 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                // SSE Streaming Text Preview (only for transcription streaming)
                if state.isStreaming && !state.streamingChunks.isEmpty {
                    streamingTextPreview
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor.opacity(0.7))
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            )
            .shadow(
                color: Color.black.opacity(0.03),
                radius: 2,
                x: 0,
                y: 1
            )
        }
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                removal: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.95))
            )
        )
        .onChange(of: state.progress) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedProgress = newValue
            }
        }
        .onAppear {
            // Initial animation when view appears
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = state.progress
            }
        }
    }
    
    // SSE Streaming text preview with precise, animated scrolling
    private var streamingTextPreview: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    // Using the full array directly for stable IDs
                    let chunks = state.streamingChunks
                    ForEach(Array(chunks.enumerated()), id: \.offset) { index, chunk in
                        Text(chunk)
                            .font(.caption)
                            .lineLimit(nil)
                            .foregroundStyle(
                                index == chunks.count - 1 ?
                                Color(NSColor.labelColor) :
                                Color(NSColor.labelColor).opacity(0.6)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index) // Use stable index as ID
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(height: 56) // ~3 lines
            .mask(
                // Taller gradient mask to properly fade the top edge
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.35),
                        .init(color: .black, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: state.streamingChunks.count) { _, newCount in
                guard newCount > 0 else { return }
                
                // Asynchronously scroll to ensure the view has updated before scrolling
                DispatchQueue.main.async {
                    withAnimation(.linear(duration: 0.2)) {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
    
    private func colorForState(_ state: ProcessingState) -> Color {
        switch state {
        case .idle:
            return secondaryTextColor
        case .transcribing:
            return primaryColor
        case .streamingTranscription:
            return primaryColor
        case .summarizing:
            return primaryColor
        case .completed:
            return .green
        case .error:
            return .red
        }
    }
}

// Preview
#Preview {
    VStack(spacing: 20) {
        ProcessingProgressView(state: .transcribing)
        ProcessingProgressView(state: .summarizing)
        ProcessingProgressView(state: .completed)
        ProcessingProgressView(state: .error("Connection failed"))
        
        // Test SSE streaming with chunks
        ProcessingProgressView(state: .streamingTranscription([
            "I want to make sure that this actually works",
            "let me verify that this is indeed working",
            "checking if streaming functionality is operational",
            "these are the last few words of transcription",
            "final chunk for testing purposes"
        ]))
    }
    .padding()
    .frame(width: 400)
} 
