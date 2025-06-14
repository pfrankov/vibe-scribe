import SwiftUI

// Processing states for the audio pipeline
enum ProcessingState {
    case idle
    case transcribing
    case summarizing
    case completed
    case error(String)
    
    var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .transcribing:
            return "Transcribing..."
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
        case .transcribing, .summarizing:
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
    
    var progress: Double {
        switch self {
        case .idle:
            return 0.0
        case .transcribing:
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
    
    private func colorForState(_ state: ProcessingState) -> Color {
        switch state {
        case .idle:
            return secondaryTextColor
        case .transcribing:
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
    }
    .padding()
    .frame(width: 400)
} 