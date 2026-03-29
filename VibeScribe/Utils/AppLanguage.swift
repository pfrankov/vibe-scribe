//
//  AppLanguage.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 09.03.2026.
//

import Foundation

enum AppLanguage {
    private static let storageKey = "ui.language.code"
    private static let uiTestingLanguageEnvKey = "VIBESCRIBE_UI_LANGUAGE_CODE"
    private static var lastAppliedAppleLanguages: String?

    private static var uiTestingOverrideCode: String? {
        let raw = ProcessInfo.processInfo.environment[uiTestingLanguageEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw : nil
    }

    private static func resolvedCode(from code: String) -> String {
        if let uiTestingOverrideCode {
            return uiTestingOverrideCode
        }
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the app language code stored in user defaults (empty string = system language).
    static var storedCode: String {
        if let uiTestingOverrideCode {
            return uiTestingOverrideCode
        }
        return UserDefaults.standard.string(forKey: storageKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Computes a Locale for a given language code or falls back to the system locale.
    static func locale(for code: String) -> Locale {
        let normalized = resolvedCode(from: code)
        return normalized.isEmpty ? .autoupdatingCurrent : Locale(identifier: normalized)
    }

    /// The locale that should be used across the app right now.
    static var currentLocale: Locale {
        locale(for: storedCode)
    }

    /// Applies the preferred language to Foundation lookups (used by NSLocalizedString)
    /// so managers and AppKit components also respect the override.
    static func applyPreferredLanguagesIfNeeded(code: String) {
        let normalized = resolvedCode(from: code)
        guard normalized != lastAppliedAppleLanguages else { return }

        lastAppliedAppleLanguages = normalized

        if normalized.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([normalized], forKey: "AppleLanguages")
        }
    }

    /// Localizes a key using the current app locale.
    static func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .main, locale: currentLocale)
    }

    /// Overload to match the signature of NSLocalizedString while ignoring the translator comment.
    static func localized(_ key: String.LocalizationValue, comment: StaticString) -> String {
        localized(key)
    }
}
