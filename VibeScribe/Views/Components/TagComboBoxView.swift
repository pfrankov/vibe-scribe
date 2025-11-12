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
        // Clean up event monitor if view is being disabled/removed
        if !nsView.isEnabled {
            context.coordinator.removeOutsideClickMonitor()
        }
        
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
        weak var activeComboBox: NSComboBox?
        var outsideClickMonitor: Any?
        var dropdownOpenedByMouse = false
        var isPopupVisible = false

        init(_ parent: TagComboBoxView) {
            self.parent = parent
            self.allOptions = parent.options
            self.filtered = parent.options
            self.usage = parent.usageCounts
        }

        deinit {
            removeOutsideClickMonitor()
        }

        // MARK: - NSComboBoxDelegate
        func comboBoxWillPopUp(_ notification: Notification) {
            dropdownOpenedByMouse = Self.isMouseEvent(NSApp?.currentEvent)
            // Don't show dropdown if there are no items to display
            guard !filtered.isEmpty else {
                // Cancel the popup by returning to the field
                DispatchQueue.main.async { [weak self] in
                    guard let self, let combo = notification.object as? NSComboBox else { return }
                    self.preventDropdownDisplay(for: combo)
                }
                return
            }
            isPopupVisible = true
        }

        /// Prevents dropdown display when there are no items to show
        private func preventDropdownDisplay(for combo: NSComboBox) {
            combo.window?.makeFirstResponder(combo)
        }

        func comboBoxWillDismiss(_ notification: Notification) {
            dropdownOpenedByMouse = false
            isPopupVisible = false
        }


        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard dropdownOpenedByMouse,
                  let combo = notification.object as? NSComboBox else { return }
            DispatchQueue.main.async { [weak self, weak combo] in
                guard let self, let combo else { return }
                self.commitSelection(from: combo)
            }
        }

        // MARK: - NSControlTextEditingDelegate
        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocusChange(true)
            if let field = obj.object as? NSComboBox {
                activeComboBox = field
                installOutsideClickMonitor(for: field)
            }
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
            activeComboBox = nil
            removeOutsideClickMonitor()
            
            let trimmedText = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return }
            
            let ok = parent.onCommit(nil)
            if ok {
                resetField(field)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                return handleArrowDown(in: control)
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                return handleEnterKey(in: control, textView: textView)
            case #selector(NSResponder.cancelOperation(_:)):
                handleEscapeKey(in: control, textView: textView)
                return true
            default:
                return false
            }
        }

        /// Handles arrow down key - prevents dropdown if no items
        private func handleArrowDown(in control: NSControl) -> Bool {
            return control is NSComboBox && filtered.isEmpty // Return true to prevent default behavior when no items
        }

        /// Handles Enter/Return key to commit selection or text
        private func handleEnterKey(in control: NSControl, textView: NSTextView) -> Bool {
            guard let combo = control as? NSComboBox else { return false }
            
            let value = selectedValue(from: combo)
            parent.text = value ?? combo.stringValue
            let ok = parent.onCommit(value)
            
            if ok {
                resetField(combo, editor: textView)
                dismissDropdown(for: combo)
                if value != nil {
                    dropdownOpenedByMouse = false
                }
            }
            return true
        }

        /// Handles Escape key to abort editing
        private func handleEscapeKey(in control: NSControl, textView: NSTextView) {
            guard let field = control as? NSComboBox else { return }
            resetField(field, editor: textView)
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(nil)
            }
        }

        // MARK: - Private helpers

        /// Commits a selection from dropdown or typed text
        private func commitSelection(from combo: NSComboBox) {
            let value = selectedValue(from: combo) ?? trimmedNonEmpty(combo.stringValue)
            guard let value else { return }

            parent.text = value
            let ok = parent.onCommit(value)
            if ok {
                resetField(combo)
                dismissDropdown(for: combo)
            }
            dropdownOpenedByMouse = false
        }

        /// Resets the field state and clears content
        private func resetField(_ field: NSComboBox, editor: NSText? = nil) {
            parent.text = ""
            field.stringValue = ""
            
            let targetEditor = editor as? NSTextView ?? field.currentEditor() as? NSTextView
            targetEditor?.string = ""
            targetEditor?.selectedRange = NSRange(location: 0, length: 0)
            
            updateFilter(for: "")
            field.reloadData()
            field.noteNumberOfItemsChanged()
            updateWidth(for: field, baseMin: parent.initialMinWidth, gap: parent.trailingGap)
        }

        /// Installs a monitor to detect clicks outside the combo box
        private func installOutsideClickMonitor(for combo: NSComboBox) {
            removeOutsideClickMonitor()
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak combo] event in
                guard let self, let combo else { return event }
                self.handleOutsideClick(event, combo: combo)
                return event
            }
        }

        /// Handles clicks outside the combo box to dismiss focus
        /// - Parameter event: The mouse event
        /// - Parameter combo: The combo box to check against
        private func handleOutsideClick(_ event: NSEvent, combo: NSComboBox) {
            guard event.window === combo.window,
                  isComboFirstResponder(combo) else { return }
            
            // Convert from window coordinates (nil = window coordinate space)
            let locationInWindow = event.locationInWindow
            let convertedLocation = combo.convert(locationInWindow, from: nil)
            guard !combo.bounds.contains(convertedLocation) else { return }
            
            DispatchQueue.main.async { [weak self, weak combo] in
                guard let self, let combo, self.isComboFirstResponder(combo) else { return }
                combo.window?.makeFirstResponder(nil)
            }
        }

        /// Removes the outside click monitor
        fileprivate func removeOutsideClickMonitor() {
            if let monitor = outsideClickMonitor {
                NSEvent.removeMonitor(monitor)
                outsideClickMonitor = nil
            }
        }

        /// Checks if the combo box or its editor is the first responder
        private func isComboFirstResponder(_ combo: NSComboBox) -> Bool {
            guard let responder = combo.window?.firstResponder else { return false }
            return responder === combo ||
                   (combo.currentEditor() != nil && responder === combo.currentEditor())
        }

        private static func isMouseEvent(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            switch event.type {
            case .leftMouseDown, .leftMouseUp,
                 .rightMouseDown, .rightMouseUp,
                 .otherMouseDown, .otherMouseUp:
                return true
            default:
                return false
            }
        }

        /// Gets the selected value from the combo box if any
        private func selectedValue(from combo: NSComboBox) -> String? {
            let index = combo.indexOfSelectedItem
            guard index >= 0 && index < filtered.count else { return nil }
            return trimmedNonEmpty(filtered[index])
        }

        /// Trims whitespace and returns nil if empty
        private func trimmedNonEmpty(_ string: String) -> String? {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        /// Dismisses the dropdown if visible
        /// - Note: Uses private API selectors as a last resort; wrapped in main thread for safety
        private func dismissDropdown(for combo: NSComboBox) {
            guard isPopupVisible else { return }
            isPopupVisible = false
            dropdownOpenedByMouse = false
            
            guard let cell = combo.cell as? NSComboBoxCell else { return }
            
            // Try to dismiss using private API methods (thread-safe)
            let dismissSelectors = [
                NSSelectorFromString("dismissPopUp:"),
                NSSelectorFromString("closePopUp:")
            ]
            
            DispatchQueue.main.async {
                for selector in dismissSelectors {
                    if cell.responds(to: selector) {
                        cell.perform(selector, with: nil)
                        break
                    }
                }
            }
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

        /// Returns the number of items in the dropdown
        func numberOfItems(in comboBox: NSComboBox) -> Int {
            // Return 0 if filtered is empty to prevent empty dropdown
            return filtered.isEmpty ? 0 : filtered.count
        }

        /// Returns the object value for the given index
        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            guard filtered.indices.contains(index) else { return nil }
            return filtered[index]
        }

        /// Finds the index of an item with the given string value
        func comboBox(_ comboBox: NSComboBox, indexOfItemWithStringValue string: String) -> Int {
            filtered.firstIndex { 
                $0.compare(string, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame 
            } ?? NSNotFound
        }

        /// Returns the completed string for autocomplete
        func comboBox(_ comboBox: NSComboBox, completedString string: String) -> String? {
            guard !filtered.isEmpty else { return nil }
            let lower = string.lowercased()
            return allOptions.first { $0.lowercased().hasPrefix(lower) }
        }
    }
}
