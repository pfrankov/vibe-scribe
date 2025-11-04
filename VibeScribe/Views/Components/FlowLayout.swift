//
//  FlowLayout.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 15.04.2025.
//

import SwiftUI

/// A lightweight wrapping layout for rendering tag capsules inline.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let maxWidth = proposal.width ?? .infinity
        var currentLineWidth: CGFloat = 0
        var currentLineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var measuredMaxLineWidth: CGFloat = 0

        for subview in subviews {
            let viewSize = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: proposal.height))

            if currentLineWidth > 0 && currentLineWidth + spacing + viewSize.width > maxWidth && maxWidth != .infinity {
                measuredMaxLineWidth = max(measuredMaxLineWidth, currentLineWidth)
                totalHeight += currentLineHeight + lineSpacing
                currentLineWidth = viewSize.width
                currentLineHeight = viewSize.height
            } else {
                if currentLineWidth > 0 {
                    currentLineWidth += spacing
                }
                currentLineWidth += viewSize.width
                currentLineHeight = max(currentLineHeight, viewSize.height)
            }
        }

        totalHeight += currentLineHeight
        measuredMaxLineWidth = max(measuredMaxLineWidth, currentLineWidth)

        let resolvedWidth: CGFloat
        if maxWidth == .infinity {
            resolvedWidth = measuredMaxLineWidth
        } else {
            resolvedWidth = min(maxWidth, measuredMaxLineWidth)
        }

        return CGSize(width: resolvedWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        let maxWidth = bounds.width
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var currentLineHeight: CGFloat = 0

        for subview in subviews {
            let viewSize = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: proposal.height))

            if origin.x > bounds.minX && origin.x + viewSize.width > bounds.maxX {
                origin.x = bounds.minX
                origin.y += currentLineHeight + lineSpacing
                currentLineHeight = 0
            }

            subview.place(
                at: CGPoint(x: origin.x, y: origin.y),
                proposal: ProposedViewSize(width: viewSize.width, height: viewSize.height)
            )

            origin.x += viewSize.width + spacing
            currentLineHeight = max(currentLineHeight, viewSize.height)
        }
    }
}
