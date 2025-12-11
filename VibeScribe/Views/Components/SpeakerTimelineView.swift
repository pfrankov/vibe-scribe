//
//  SpeakerTimelineView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 20.05.2025.
//

import SwiftUI
import Foundation

struct SpeakerTimelineSegment: Identifiable, Hashable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    let hue: Double
    let label: String

    var duration: TimeInterval {
        endTime - startTime
    }
}

struct SpeakerTimelineView: View {
    let duration: TimeInterval
    let playbackTime: TimeInterval
    let segments: [SpeakerTimelineSegment]
    let onSeek: (TimeInterval) -> Void
    var minTapWidth: CGFloat = 24

    private func color(for hue: Double) -> Color {
        Color(hue: hue, saturation: 0.72, brightness: 0.9, opacity: 0.95)
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = max(geometry.size.width, 1)
            let barHeight = max(18, geometry.size.height - 10)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .allowsHitTesting(false)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )

                ForEach(collapsedSegments(totalWidth: totalWidth)) { segment in
                    let rawWidth = width(for: segment, totalWidth: totalWidth)
                    let visualWidth = max(rawWidth, 2)
                    let startX = offset(for: segment, totalWidth: totalWidth)

                    Button {
                        onSeek(segment.startTime)
                    } label: {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color(for: segment.hue))
                            if visualWidth > 90 {
                                Text(segment.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.primary)
                                    .padding(.horizontal, 8)
                                    .frame(height: barHeight, alignment: .center)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(width: visualWidth, height: barHeight)
                    .position(x: startX + visualWidth / 2, y: geometry.size.height / 2)
                }

                let playheadX = playheadOffset(totalWidth: totalWidth)
                Rectangle()
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: 2, height: geometry.size.height - 2)
                    .offset(x: playheadX)
                    .accessibilityLabel(Text(AppLanguage.localized("playhead")))
            }
        }
        .frame(height: 38)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(AppLanguage.localized("speaker.timeline")))
    }

    private func width(for segment: SpeakerTimelineSegment, totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let clampedDuration = max(0, min(segment.duration, duration))
        return CGFloat(clampedDuration / duration) * totalWidth
    }

    private func offset(for segment: SpeakerTimelineSegment, totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let start = max(0, min(segment.startTime, duration))
        return CGFloat(start / duration) * totalWidth
    }

    private func playheadOffset(totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let clamped = min(max(playbackTime / duration, 0), 1)
        return CGFloat(clamped) * totalWidth
    }

    private func collapsedSegments(totalWidth: CGFloat) -> [SpeakerTimelineSegment] {
        guard !segments.isEmpty else { return [] }
        let minWidth = minTapWidth

        func combine(_ group: [SpeakerTimelineSegment]) -> SpeakerTimelineSegment {
            let start = group.first!.startTime
            let end = group.last!.endTime

            var durationByLabel: [String: TimeInterval] = [:]
            var hueByLabel: [String: Double] = [:]
            for seg in group {
                durationByLabel[seg.label, default: 0] += seg.duration
                hueByLabel[seg.label] = seg.hue
            }
            let dominant = durationByLabel.max(by: { $0.value < $1.value })?.key ?? group.first!.label
            let dominantHue = hueByLabel[dominant] ?? group.first!.hue

            return SpeakerTimelineSegment(
                id: UUID(),
                startTime: start,
                endTime: end,
                hue: dominantHue,
                label: dominant
            )
        }

        var result: [SpeakerTimelineSegment] = []
        var buffer: [SpeakerTimelineSegment] = []
        var bufferWidth: CGFloat = 0

        func flush() {
            if !buffer.isEmpty {
                result.append(combine(buffer))
                buffer.removeAll()
                bufferWidth = 0
            }
        }

        let ordered = segments.sorted { $0.startTime < $1.startTime }

        for segment in ordered {
            let w = width(for: segment, totalWidth: totalWidth)
            if w >= minWidth && buffer.isEmpty {
                result.append(segment)
            } else {
                buffer.append(segment)
                bufferWidth += w
                if bufferWidth >= minWidth {
                    flush()
                }
            }
        }
        if !buffer.isEmpty {
            if bufferWidth < minWidth, let last = result.popLast() {
                buffer.insert(last, at: 0)
            }
            flush()
        }
        return result
    }
}
