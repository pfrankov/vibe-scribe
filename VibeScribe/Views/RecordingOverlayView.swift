import SwiftUI
import AppKit
import SwiftData

struct RecordingOverlayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var manager = CombinedAudioRecorderManager()
    @State private var isSending = false

    // Layout constants (single source of truth)
    private let cornerRadius: CGFloat = 22
    private let outerPadding: CGFloat = 24 // More space so shadow never clips
    private let edgePadding: CGFloat = 18
    private let controlHeight: CGFloat = 46
    private let contentWidth: CGFloat = 300

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                header
                controls
            }
            .padding(edgePadding)
            .frame(width: contentWidth)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.12), lineWidth: 1)
            )
            // Rely on system window shadow (NSPanel.hasShadow)
            .compositingGroup()
        }
        // Let the view size to its content; keep small padding for outside shadow
        .padding(outerPadding)
        .onAppear { manager.startRecording() }
    }

    // MARK: - Header
    private var header: some View {
        ZStack {
            // Centered time
            Text(manager.recordingTime.clockString)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)

            // Leading/Trailing controls
            HStack(spacing: 8) {
                Button {
                    OverlayWindowManager.shared.presentDiscardConfirm(
                        onDiscard: { discardAndClose() },
                        onCancel: {}
                    )
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(AppLanguage.localized("close")))

                Spacer(minLength: 8)

                sourcesAndWave
            }
        }
        .frame(height: 20)
    }

    private var sourcesAndWave: some View {
        HStack(spacing: 6) {
            // Source icons
            Image(systemName: "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(0.8)
                .help(AppLanguage.localized("microphone.source"))

            if manager.isSystemAudioEnabled {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(0.8)
                    .help(AppLanguage.localized("system.audio.is.captured.when.available"))
            }

            // Compact monochrome waveform (taller, slightly narrower)
            MiniWaveformView(levels: manager.audioLevels)
                .frame(width: 32, height: 18)
                .opacity(manager.isPaused ? 0.2 : 1)
                .animation(.easeInOut(duration: 0.2), value: manager.isPaused)
        }
        .help(AppLanguage.localized("audio.source.indicators.microphone.and.system.audio"))
    }

    // MARK: - Controls
    private var controls: some View {
        HStack(spacing: 12) {
            if manager.isPaused {
                Button {
                    manager.resumeRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text(AppLanguage.localized("resume"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillFilledButtonStyle(color: Color(NSColor.systemGray), height: controlHeight, textColor: .white))

                Button {
                    sendAndFinish()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                        Text(AppLanguage.localized("save"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PillFilledButtonStyle(color: Color.accentColor, height: controlHeight, textColor: .white))
                .disabled(isSending)
            } else {
                Button {
                    manager.pauseRecording()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.fill")
                        Text(AppLanguage.localized("stop"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    PillTintedButtonStyle(
                        color: .red,
                        height: controlHeight
                    )
                )
                .keyboardShortcut(.escape)
            }
        }
    }

    // MARK: - Actions
    private func sendAndFinish() {
        guard !isSending else { return }
        isSending = true
        if let result = manager.stopRecording() {
            createAndSaveRecord(url: result.url, duration: result.duration, includesSystemAudio: result.includesSystemAudio)
        }
        isSending = false
        OverlayWindowManager.shared.close()
    }

    private func discardAndClose() {
        manager.cancelRecording()
        OverlayWindowManager.shared.close()
    }

    private func createAndSaveRecord(url: URL, duration: TimeInterval, includesSystemAudio: Bool) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let name = String(
            format: AppLanguage.localized("recording.arg1", comment: "Default recording name with timestamp"),
            formatter.string(from: Date())
        )
        let newRecord = Record(name: name, fileURL: url, duration: duration, includesSystemAudio: includesSystemAudio)
        modelContext.insert(newRecord)
        do {
            try modelContext.save()
            NotificationCenter.default.post(name: NSNotification.Name("NewRecordCreated"), object: nil, userInfo: ["recordId": newRecord.id])
        } catch {
            Logger.error("Failed to save record from overlay", error: error, category: .audio)
        }
    }
}

// Compact waveform used in overlay (monochrome)
private struct MiniWaveformView: View {
    var levels: [Float]
    var body: some View {
        GeometryReader { geo in
            let barCount = min(levels.count, 8)
            let spacing: CGFloat = 2.5
            let barWidth = (geo.size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount)
            HStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color.secondary.opacity(0.65))
                        .frame(width: barWidth, height: max(1, CGFloat(levels[i]) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.linear(duration: 0.08), value: levels)
        }
    }
}

// MARK: - Button Styles
private struct PillFilledButtonStyle: ButtonStyle {
    var color: Color
    var height: CGFloat
    var textColor: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(
                Capsule().fill(color)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// A softer, tinted variant (used for Stop)
private struct PillTintedButtonStyle: ButtonStyle {
    var color: Color
    var height: CGFloat
    // Slightly opaque tint that remains readable over material backgrounds
    var fillOpacityLight: Double = 0.16
    var fillOpacityDark: Double = 0.22
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        let fillOpacity = colorScheme == .dark ? fillOpacityDark : fillOpacityLight
        return configuration.label
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .frame(height: height)
            .background(
                Capsule()
                    .fill(color.opacity(fillOpacity))
            )
            // No shadow per request
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
//
