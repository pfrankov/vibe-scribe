//
//  TextEditorSizing.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import AppKit
import Foundation

/// Utility helpers for sizing multi-line text editors based on font metrics.
enum TextEditorSizing {
    /// Returns the line height for a given font using its raw metrics.
    static func lineHeight(for font: NSFont) -> CGFloat {
        font.ascender + abs(font.descender) + font.leading
    }

    /// Calculates the minimum height needed to display a specific number of lines (without padding).
    static func minimumContentHeight(for font: NSFont, minimumLines: Int) -> CGFloat {
        let clampedLines = max(minimumLines, 1)
        return lineHeight(for: font) * CGFloat(clampedLines)
    }

    /// Measures the height of the provided text for a given width and font (without padding).
    static func contentHeight(for text: String, font: NSFont, width: CGFloat) -> CGFloat {
        guard width > 0 else {
            return minimumContentHeight(for: font, minimumLines: 1)
        }

        let normalized = normalizedText(from: text)

        let storage = NSTextStorage(string: normalized)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0

        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))

        layoutManager.glyphRange(for: container)
        let rect = layoutManager.usedRect(for: container)
        return ceil(rect.height)
    }

    private static func normalizedText(from text: String) -> String {
        text.isEmpty ? " " : text
    }
}
