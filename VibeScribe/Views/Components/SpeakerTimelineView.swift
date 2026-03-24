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
    let mergeKey: String

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
            let visibleSegments = collapsedSegments(totalWidth: totalWidth)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .allowsHitTesting(false)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )

                ForEach(Array(visibleSegments.enumerated()), id: \.element.id) { index, segment in
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
                    .offset(x: startX, y: (geometry.size.height - barHeight) / 2)
                    .accessibilityIdentifier("\(AccessibilityID.speakerTimelineSegmentPrefix)\(index)")
                    .accessibilityLabel(Text(segment.label))
                    .accessibilityValue(Text("\(clockString(from: segment.startTime))-\(clockString(from: segment.endTime))"))
                    .accessibilityAction {
                        onSeek(segment.startTime)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            onSeek(segment.startTime)
                        }
                    )
                }

                let playheadX = playheadOffset(totalWidth: totalWidth)
                Rectangle()
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: 2, height: geometry.size.height - 2)
                    .offset(x: playheadX)
                    .allowsHitTesting(false)
                    .accessibilityLabel(Text(AppLanguage.localized("playhead")))
            }
        }
        .frame(height: 38)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(AppLanguage.localized("speaker.timeline")))
        .accessibilityIdentifier(AccessibilityID.speakerTimeline)
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
        guard !segments.isEmpty, duration > 0, totalWidth > 0 else {
            return segments.sorted { $0.startTime < $1.startTime }
        }
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        // Pass 1: merge consecutive same-speaker segments separated by short pauses.
        let runs = mergeSameSpeakerRuns(sorted, maxGap: 3.0)
        // Pass 2: absorb any segment narrower than 4 px into its predecessor.
        return absorbTinySegments(runs, totalWidth: totalWidth, minPx: 4)
    }

    /// Merges consecutive same-speaker segments whose gap is at most `maxGap` seconds.
    private func mergeSameSpeakerRuns(
        _ sorted: [SpeakerTimelineSegment],
        maxGap: TimeInterval
    ) -> [SpeakerTimelineSegment] {
        var result: [SpeakerTimelineSegment] = []
        for seg in sorted {
            if let last = result.last,
               last.mergeKey == seg.mergeKey,
               seg.startTime - last.endTime <= maxGap {
                result[result.count - 1] = SpeakerTimelineSegment(
                    id: last.id,
                    startTime: last.startTime,
                    endTime: max(last.endTime, seg.endTime),
                    hue: last.hue,
                    label: last.label,
                    mergeKey: last.mergeKey
                )
            } else {
                result.append(seg)
            }
        }
        return result
    }

    /// Absorbs any segment whose rendered width is below `minPx` into its predecessor,
    /// keeping the predecessor's speaker identity.
    private func absorbTinySegments(
        _ sorted: [SpeakerTimelineSegment],
        totalWidth: CGFloat,
        minPx: CGFloat
    ) -> [SpeakerTimelineSegment] {
        guard sorted.count > 1 else { return sorted }
        var result: [SpeakerTimelineSegment] = []
        for seg in sorted {
            let px = CGFloat(seg.duration / duration) * totalWidth
            if px < minPx, let last = result.last {
                result[result.count - 1] = SpeakerTimelineSegment(
                    id: last.id,
                    startTime: last.startTime,
                    endTime: max(last.endTime, seg.endTime),
                    hue: last.hue,
                    label: last.label,
                    mergeKey: last.mergeKey
                )
            } else {
                result.append(seg)
            }
        }
        return result
    }

    private func clockString(from time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
