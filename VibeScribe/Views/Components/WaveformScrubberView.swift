import SwiftUI

struct WaveformScrubberView: View {
    @Binding var progress: Double // 0...1 normalized progress
    var samples: [Float]
    var duration: TimeInterval = 0
    var isEnabled: Bool = true
    var onScrubStart: (() -> Void)?
    var onScrubChange: ((Double) -> Void)?
    var onScrubEnd: ((Double) -> Void)?

    @State private var isDragging = false
    @State private var lastDragLocation: CGFloat? = nil
    @Environment(\.colorScheme) private var colorScheme

    private let cornerRadius: CGFloat = 8
    private let minBarHeightFactor: CGFloat = 0.03
    private let highlightLineWidth: CGFloat = 2
    private let horizontalInset: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack(alignment: .leading) {
                shape
                    .fill(Color(NSColor.controlBackgroundColor).opacity(colorScheme == .dark ? 0.75 : 0.95))
                // Subtle filled region for played portion (independent of bar heights)
                progressFill(width: geometry.size.width)
                if samples.isEmpty {
                    loadingPlaceholder
                } else {
                    waveformBars(in: geometry.size)
                }
                progressIndicator(width: geometry.size.width)
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(Color.black.opacity(colorScheme == .dark ? 0.24 : 0.08), lineWidth: 0.6)
            )
            .contentShape(shape)
            .gesture(dragGesture(width: geometry.size.width))
            .allowsHitTesting(isEnabled)
        }
        .frame(height: 56)
    }

    private func progressFill(width: CGFloat) -> some View {
        let clamped = CGFloat(max(0, min(1, progress)))
        let effectiveWidth = max(width - horizontalInset * 2, 0)
        // Fill starts at track's left edge and ends at the indicator's center position
        let fillWidth = max(0, min(width, horizontalInset + clamped * effectiveWidth))
        return Rectangle()
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: fillWidth)
    }

    private var trackBackground: some View { EmptyView() }

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius - 2, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .padding(.horizontal, horizontalInset)
    }

    private func waveformBars(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard !samples.isEmpty else { return }

            let baseSamples = samplesForRendering(width: canvasSize.width)
            let renderSamples = applyLocalContrast(baseSamples, duration: duration)
            guard !renderSamples.isEmpty else { return }

            let barCount = renderSamples.count
            let clampedProgress = max(0, min(1, progress))
            let effectiveWidth = max(canvasSize.width - horizontalInset * 2, 1)
            let spacing = max(0.4, min(2.0, effectiveWidth / CGFloat(max(barCount * 6, 1))))
            let totalSpacing = spacing * CGFloat(max(barCount - 1, 0))
            let availableWidth = max(effectiveWidth - totalSpacing, 0)
            let barWidth = max(1.0, availableWidth / CGFloat(max(barCount, 1)))
            let midY = canvasSize.height / 2
            let activeColor = Color.accentColor
            let inactiveColor = Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.18)
            let minHeight = max(1, canvasSize.height * minBarHeightFactor)
            let progressPosition = clampedProgress * effectiveWidth

            var x = horizontalInset

            for index in 0..<barCount {
                let amplitude = CGFloat(max(0, min(1, renderSamples[index])))
                let barHeight = max(minHeight, amplitude * canvasSize.height)
                let rect = CGRect(
                    x: x,
                    y: midY - barHeight / 2,
                    width: barWidth,
                    height: barHeight
                )

                let leading = x - horizontalInset
                let trailing = leading + barWidth
                let isBefore = progressPosition >= trailing
                let isCurrent = !isBefore && progressPosition > leading
                let fillColor: Color
                if isBefore {
                    fillColor = activeColor
                } else if isCurrent {
                    let proportion = max(0, min(1, (progressPosition - leading) / max(barWidth, 0.001)))
                    fillColor = activeColor.opacity(0.35 + 0.45 * proportion)
                } else {
                    fillColor = inactiveColor
                }

                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(fillColor))
                x += barWidth + spacing
            }
        }
        .padding(.horizontal, 0)
    }

    private func progressIndicator(width: CGFloat) -> some View {
        let clampedProgress = CGFloat(max(0, min(1, progress)))
        let effectiveWidth = max(width - horizontalInset * 2, 0)
        let rawX = horizontalInset + clampedProgress * effectiveWidth - highlightLineWidth / 2
        let minX = horizontalInset
        let maxX = max(width - horizontalInset - highlightLineWidth, minX)
        let indicatorX = max(minX, min(maxX, rawX))
        return Rectangle()
            .fill(Color.accentColor.opacity(isDragging ? 0.9 : 0.7))
            .frame(width: highlightLineWidth)
            .offset(x: indicatorX)
            .shadow(color: Color.accentColor.opacity(0.2), radius: isDragging ? 3 : 1, x: 0, y: 0)
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEnabled else { return }
                if !isDragging {
                    isDragging = true
                    onScrubStart?()
                }

                let ratio = normalizedProgress(for: value.location.x, width: width)
                progress = ratio
                onScrubChange?(ratio)
                lastDragLocation = value.location.x
            }
            .onEnded { value in
                guard isEnabled else { return }
                let ratio: Double
                if let last = lastDragLocation {
                    ratio = normalizedProgress(for: last, width: width)
                } else {
                    ratio = normalizedProgress(for: value.location.x, width: width)
                }
                progress = ratio
                onScrubEnd?(ratio)
                isDragging = false
                lastDragLocation = nil
            }
    }

    private func normalizedProgress(for locationX: CGFloat, width: CGFloat) -> Double {
        let effectiveWidth = max(width - horizontalInset * 2, 1)
        let clampedX = max(horizontalInset, min(locationX, width - horizontalInset))
        return Double((clampedX - horizontalInset) / effectiveWidth)
    }

    private func samplesForRendering(width: CGFloat) -> [Float] {
        guard width > 0, !samples.isEmpty else { return samples }

        let effectiveWidth = max(width - horizontalInset * 2, 1)
        let approximateBars = max(18, Int(effectiveWidth / 2.0))
        let targetBars = min(samples.count, approximateBars)

        guard targetBars > 0 else { return samples }
        if samples.count <= targetBars { return samples }

        let chunkSize = Double(samples.count) / Double(targetBars)
        var condensed: [Float] = []
        condensed.reserveCapacity(targetBars)

        for index in 0..<targetBars {
            let start = Int(Double(index) * chunkSize)
            let end = Int(Double(index + 1) * chunkSize)
            let safeStart = min(samples.count - 1, start)
            let safeEnd = min(samples.count, max(end, safeStart + 1))

            var maxValue: Float = 0
            var sumSquares: Double = 0
            let count = safeEnd - safeStart

            if count > 0 {
                for i in safeStart..<safeEnd {
                    let value = samples[i]
                    maxValue = max(maxValue, value)
                    sumSquares += Double(value * value)
                }
            }

            let rms = count > 0 ? Float(sqrt(sumSquares / Double(count))) : 0
            // Favor peaks; use a little RMS to keep structure
            let composite = max(maxValue, rms * 0.5)
            condensed.append(max(0, min(1.0, composite)))
        }

        // Do not re-normalize to local max here; keep global normalization from manager
        return condensed
    }

    // MARK: - Local contrast (windowed normalization)
    private func applyLocalContrast(_ input: [Float], duration: TimeInterval) -> [Float] {
        let n = input.count
        guard n > 0, duration > 0 else { return input }

        // Continuous mapping: t grows with duration, saturates around 2 hours
        let t = min(1.0, log(1 + duration) / log(1 + 7200)) // 0..1

        // Window seconds increase smoothly with duration (6s..40s)
        let windowSeconds = 6.0 + 34.0 * t

        // Quantiles move toward median for long tracks to boost contrast locally
        let qLo = 0.06 + 0.12 * t   // 0.06..0.18
        let qHi = 0.94 - 0.12 * t   // 0.94..0.82

        // Blend factor: more weight to local view on long tracks
        let localBlend = 0.55 + 0.30 * t // 0.55..0.85

        // Convert to half-window bars
        let barsPerSecond = Double(n) / duration
        var w = Int(ceil(barsPerSecond * windowSeconds / 2.0))
        w = max(2, min(n / 2, w))

        func percentile(_ arr: ArraySlice<Float>, _ p: Double) -> Float {
            let count = arr.count
            if count <= 1 { return arr.first ?? 0 }
            let sorted = arr.sorted()
            let pos = min(max(p, 0), 1) * Double(count - 1)
            let lower = Int(floor(pos))
            let upper = Int(ceil(pos))
            if lower == upper { return sorted[lower] }
            let tt = Float(pos - Double(lower))
            return sorted[lower] * (1 - tt) + sorted[upper] * tt
        }

        var out = input
        for i in 0..<n {
            let loIndex = max(0, i - w)
            let hiIndex = min(n - 1, i + w)
            let window = input[loIndex...hiIndex]
            let lo = percentile(window, qLo)
            let hi = percentile(window, qHi)
            let span = max(hi - lo, 1e-4)
            let local = max(0, min(1, (input[i] - lo) / span))
            // Blend local with global to keep overall outline
            out[i] = max(0, min(1, Float(localBlend) * local + Float(1 - localBlend) * input[i]))
        }

        // Slight shaping to keep micro-variation visible
        return out.map { powf($0, 0.96) }
    }
}

struct WaveformScrubberView_Previews: PreviewProvider {
    static var previews: some View {
        WaveformScrubberView(
            progress: .constant(0.35),
            samples: stride(from: 0.1, through: 1.0, by: 0.02).map { Float(abs(sin($0 * 3))) },
            isEnabled: true
        )
        .frame(height: 56)
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
