//
//  TagManager.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 15.04.2025.
//

import Foundation
import SwiftData

@MainActor
final class TagManager: ObservableObject {
    static let shared = TagManager()

    private init() {}

    /// Finds an existing tag or creates a new one if none is found.
    @discardableResult
    func ensureTag(named rawName: String, in context: ModelContext) throws -> Tag? {
        let trimmed = normalizedName(from: rawName)
        guard !trimmed.isEmpty else { return nil }

        if let existing = try fetchTag(named: trimmed, in: context) {
            return existing
        }

        let tag = Tag(name: trimmed)
        context.insert(tag)
        Logger.debug("Created new tag: \(trimmed)", category: .data)
        return tag
    }

    /// Attaches the provided tag to the record and ensures the tag maintains a backlink.
    /// - Returns: `true` if any changes were made.
    @discardableResult
    func attach(_ tag: Tag, to record: Record) -> Bool {
        var didChange = false

        if !record.tags.contains(where: { $0.id == tag.id }) {
            record.tags.append(tag)
            didChange = true
        }

        if !tag.records.contains(where: { $0.id == record.id }) {
            tag.records.append(record)
            didChange = true
        }

        return didChange
    }

    /// Removes the provided tag from the given record and deletes the tag model
    /// if it no longer belongs to any records.
    @discardableResult
    func detach(_ tag: Tag, from record: Record, in context: ModelContext) -> Bool {
        var didChange = false

        let originalRecordTagCount = record.tags.count
        record.tags.removeAll { $0.id == tag.id }
        if record.tags.count != originalRecordTagCount {
            didChange = true
        }

        let originalTagRecordCount = tag.records.count
        tag.records.removeAll { $0.id == record.id }
        if tag.records.count != originalTagRecordCount {
            didChange = true
        }

        if didChange {
            pruneTagIfNeeded(tag, in: context)
        }

        return didChange
    }

    /// Deletes the tag model if there are no records referencing it anymore.
    func pruneTagIfNeeded(_ tag: Tag, in context: ModelContext) {
        guard tag.records.isEmpty else { return }
        context.delete(tag)
        Logger.debug("Deleted orphaned tag: \(tag.name)", category: .data)
    }

    /// Helper to fetch a tag by name using a case-insensitive comparison.
    private func fetchTag(named name: String, in context: ModelContext) throws -> Tag? {
        var exactMatchDescriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { tag in
                tag.name == name
            }
        )
        exactMatchDescriptor.fetchLimit = 1

        if let exact = try context.fetch(exactMatchDescriptor).first {
            return exact
        }

        // Fallback to a lightweight in-memory case-insensitive lookup to avoid duplicates like "Meeting" and "meeting".
        let allTags = try context.fetch(FetchDescriptor<Tag>())
        return allTags.first { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    private func normalizedName(from rawName: String) -> String {
        rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
