//
//  TagComboBoxView.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 2025-11-05.
//

import SwiftUI
import AppKit


/// NSComboBox wrapper tailored for entering/selecting tag names.
/// - Supports editable text, completion, and commit on selection/return.
struct TagComboBoxView: NSViewRepresentable {
    var placeholder: String
    var options: [String]
    var usageCounts: [String: Int] = [:]
    var initialMinWidth: CGFloat = 72
    // Extra right-side gap so caret/text don't touch edge
    var trailingGap: CGFloat = 18
    @Binding var text: String
    // Returns true if commit successfully added/attached a tag
    var onCommit: (String?) -> Bool
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox(frame: .zero)
        combo.isEditable = true
        combo.usesDataSource = true
        combo.dataSource = context.coordinator
        combo.delegate = context.coordinator
        combo.completes = true   // enable native inline autocomplete
        combo.placeholderString = placeholder
        combo.target = context.coordinator
        combo.action = #selector(Coordinator.selectionChanged(_:))
        combo.numberOfVisibleItems = 8
        combo.stringValue = text

        // Visual tweaks to blend inline with tag chips
        combo.isButtonBordered = false     // hide dropdown arrow button border
        combo.isBezeled = false            // remove text field bezel
        combo.isBordered = false           // remove border
        combo.focusRingType = .none        // no blue focus ring
        combo.drawsBackground = false
        combo.controlSize = .mini          // keep the field compact vertically
        combo.font = .systemFont(ofSize: 13)
        combo.setContentHuggingPriority(.required, for: .horizontal)
        combo.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Start with compact width; grow as user types
        combo.translatesAutoresizingMaskIntoConstraints = false
        let c = combo.widthAnchor.constraint(equalToConstant: initialMinWidth)
        c.priority = .required
        c.isActive = true
        context.coordinator.widthConstraint = c
        return combo
    }

    func updateNSView(_ nsView: NSComboBox, context: Context) {
        // Update placeholder
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        // Refresh options in coordinator and filter accordingly
        if context.coordinator.allOptions != options || context.coordinator.usage != usageCounts {
            context.coordinator.allOptions = options
            context.coordinator.usage = usageCounts
            context.coordinator.updateFilter(for: nsView.stringValue)
            nsView.reloadData()
        }

        // Keep text in sync with the binding, even if the field is currently editing,
        // so programmatic clears (e.g. delimiter commits) don't leave stale text behind.
        let fieldEditor = nsView.currentEditor() as? NSTextView
        if nsView.stringValue != text {
            nsView.stringValue = text
            if let editor = fieldEditor {
                editor.string = text
                editor.selectedRange = NSRange(location: text.count, length: 0)
            }
            context.coordinator.updateFilter(for: text)
            nsView.reloadData()
            nsView.noteNumberOfItemsChanged()
        }

        // Grow to fit content while keeping a compact minimum
        context.coordinator.updateWidth(for: nsView, baseMin: initialMinWidth, gap: trailingGap)
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSControlTextEditingDelegate, NSComboBoxDataSource {
        var parent: TagComboBoxView
        var allOptions: [String] = []
        var filtered: [String] = []
        var usage: [String: Int] = [:]
        var widthConstraint: NSLayoutConstraint?

        init(_ parent: TagComboBoxView) {
            self.parent = parent
            self.allOptions = parent.options
            self.filtered = parent.options
            self.usage = parent.usageCounts
        }

        // MARK: - Target/Action
        @objc func selectionChanged(_ sender: NSComboBox) {
            let selected = sender.indexOfSelectedItem >= 0 ? sender.objectValueOfSelectedItem as? String : nil
            if let value = selected, !value.isEmpty {
                parent.text = value
                let ok = parent.onCommit(value)
                if ok {
                    parent.text = ""
                    sender.stringValue = ""
                    updateFilter(for: "")
                    sender.reloadData()
                    sender.noteNumberOfItemsChanged()
                    updateWidth(for: sender, baseMin: parent.initialMinWidth, gap: parent.trailingGap)
                }
            }
        }

        // MARK: - NSControlTextEditingDelegate
        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocusChange(true)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSComboBox else { return }
            let value = field.stringValue
            parent.text = value
            updateFilter(for: value)
            field.reloadData()
            field.noteNumberOfItemsChanged()
            updateWidth(for: field, baseMin: parent.initialMinWidth, gap: parent.trailingGap)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onFocusChange(false)
            guard let field = obj.object as? NSComboBox else { return }
            if !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ok = parent.onCommit(nil)
                if ok {
                    parent.text = ""
                    field.stringValue = ""
                    updateFilter(for: "")
                    field.reloadData()
                    field.noteNumberOfItemsChanged()
                    updateWidth(for: field, baseMin: parent.initialMinWidth, gap: parent.trailingGap)
                }
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Commit on Enter/Return
            if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
               commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                let ok = parent.onCommit(nil)
                if ok, let field = control as? NSComboBox {
                    parent.text = ""
                    field.stringValue = ""
                    textView.string = ""
                    updateFilter(for: "")
                    field.reloadData()
                    field.noteNumberOfItemsChanged()
                    updateWidth(for: field, baseMin: parent.initialMinWidth, gap: parent.trailingGap)
                }
                return true
            }
            return false
        }

        // MARK: - Filtering
        func updateFilter(for query: String) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                // When empty, order by usage desc then name
                filtered = allOptions.sorted(by: rankComparator(query: ""))
                return
            }
            filtered = allOptions
                .filter { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
                .sorted(by: rankComparator(query: trimmed))
        }

        private func rankComparator(query: String) -> (String, String) -> Bool {
            let q = query.lowercased()
            return { a, b in
                let ra = self.rank(for: a, query: q)
                let rb = self.rank(for: b, query: q)
                if ra != rb { return ra < rb }
                let ua = self.usage[a, default: 0]
                let ub = self.usage[b, default: 0]
                if ua != ub { return ua > ub }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        }

        private func rank(for option: String, query: String) -> Int {
            guard !query.isEmpty else { return 2 } // neutral when empty
            let s = option.lowercased()
            if s.hasPrefix(query) { return 0 }
            if let r = s.range(of: query) {
                // word-boundary prefix gets better score
                if r.lowerBound == s.startIndex { return 0 }
                let prev = s.index(before: r.lowerBound)
                if CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains(Unicode.Scalar(String(s[prev]).unicodeScalars.first!)) {
                    return 1
                }
                return 2
            }
            return 3
        }

        func updateWidth(for combo: NSComboBox, baseMin: CGFloat, gap: CGFloat) {
            let font = combo.font ?? .systemFont(ofSize: 13)

            // Measure both the current text and the placeholder and
            // pick the longest so the placeholder never truncates.
            let currentText = combo.stringValue as NSString
            let placeholderText = (combo.placeholderString ?? "") as NSString

            let currentWidth = currentText.size(withAttributes: [.font: font]).width
            let placeholderWidth = placeholderText.size(withAttributes: [.font: font]).width

            // 12 accounts for field insets; `gap` gives breathing room and space
            // for the combo button/arrow so text doesn't collide or clip.
            let measured = max(currentWidth, placeholderWidth) + 12 + gap
            let target = max(baseMin, measured)
            if abs((widthConstraint?.constant ?? 0) - target) > 0.5 {
                widthConstraint?.constant = target
            }
        }

        // MARK: - NSComboBoxDataSource
        func numberOfItems(in comboBox: NSComboBox) -> Int { filtered.count }

        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            guard index >= 0 && index < filtered.count else { return nil }
            return filtered[index]
        }

        func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int {
            if let idx = filtered.firstIndex(where: { $0.compare(string, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                return idx
            }
            return NSNotFound
        }

        func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? {
            let lower = string.lowercased()
            return allOptions.first { $0.lowercased().hasPrefix(lower) }
        }
    }
}
