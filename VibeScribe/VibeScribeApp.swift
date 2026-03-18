//
//  VibeScribeApp.swift
//  VibeScribe
//
//  Created by Pavel Frankov on 13.04.2025.
//

import SwiftUI
import SwiftData
import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem?
    var mainWindow: NSWindow?

    private var isUITestingProcess: Bool {
        let env = ProcessInfo.processInfo.environment
        return ProcessInfo.processInfo.arguments.contains("--uitesting")
            || env["VIBESCRIBE_UI_TESTING"] == "1"
            || env["VIBESCRIBE_UI_USE_MOCK_PIPELINE"] == "1"
            || env["XCTestConfigurationFilePath"] != nil
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()

        // Skip permission requests during UI testing to avoid system dialogs
        guard !isUITestingProcess else { return }

        requestPermissions { granted in
            if granted {
                Logger.info("All permissions granted", category: .general)
            } else {
                Logger.warning("Some permissions were denied", category: .general)
                // Show user notification about permissions
                DispatchQueue.main.async {
                    self.showPermissionAlert()
                }
            }
        }
    }
    
    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusBarItem?.button else { return }
        
        button.image = NSImage(named: "MenuBarIcon")
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        
        let menu = NSMenu()
        
        // Open main window
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("open"),
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        ))
        
        // Start recording
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("start.recording"),
            action: #selector(startRecording),
            keyEquivalent: "r"
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("settings"),
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit application
        menu.addItem(NSMenuItem(
            title: AppLanguage.localized("quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        
        statusBarItem?.menu = menu
    }
    
    @objc func statusBarButtonClicked() {
        if let window = mainWindow {
            if window.isVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        } else {
            openMainWindow()
        }
    }
    
    @objc func openMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else if let window = NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            mainWindow = window
        }
    }
    
    @objc func startRecording() {
        openMainWindow()
        // Notify the UI to start recording
        NotificationCenter.default.post(name: NSNotification.Name("StartRecording"), object: nil)
    }
    
    @objc func openSettings() {
        if let window = mainWindow ?? NSApplication.shared.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
            }
        }
    }
    
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        guard !isUITestingProcess else {
            completion(true)
            return
        }
        // Request Microphone access
        AVCaptureDevice.requestAccess(for: .audio) { micGranted in
            Task { @MainActor in
                await self.requestSystemAudioPermissionIfNeeded()
                completion(micGranted)
            }
        }
    }

    @MainActor
    private func requestSystemAudioPermissionIfNeeded() async {
        do {
            _ = try await SCShareableContent.current
            Logger.info("System audio permission available", category: .audio)
        } catch {
            Logger.info("System audio permission not yet available; will request when needed", category: .audio)
        }
    }
    
    private func showPermissionAlert() {
        guard !isUITestingProcess else { return }
        let alert = NSAlert()
        alert.messageText = AppLanguage.localized("microphone.permission.required")
        alert.informativeText = AppLanguage.localized("vibescribe.needs.microphone.access.to.record.audio.please.grant.permission.in.system.preferences.security.privacy.microphone")
        alert.alertStyle = .warning
        alert.addButton(withTitle: AppLanguage.localized("open.system.preferences"))
        alert.addButton(withTitle: AppLanguage.localized("cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open System Preferences
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

@main
struct VibeScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("ui.language.code") private var appLanguageCode: String = ""

    private static let hasXCTestConfiguration = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private static let uiTestingEnvEnabled = ProcessInfo.processInfo.environment["VIBESCRIBE_UI_TESTING"] == "1"
    private static let emptyStateEnvEnabled = ProcessInfo.processInfo.environment["VIBESCRIBE_UI_EMPTY_STATE"] == "1"

    static let isUITesting =
        ProcessInfo.processInfo.arguments.contains("--uitesting")
        || uiTestingEnvEnabled
        || hasXCTestConfiguration
    static let isEmptyState =
        ProcessInfo.processInfo.arguments.contains("--empty-state")
        || emptyStateEnvEnabled

    private var appLocale: Locale {
        AppLanguage.applyPreferredLanguagesIfNeeded(code: appLanguageCode)
        return AppLanguage.locale(for: appLanguageCode)
    }

    init() {
        // Keep UI-test startup deterministic even if a previous manual/dev session toggled
        // the debug empty-state switch persisted in UserDefaults.
        if Self.isUITesting {
            UserDefaults.standard.set(false, forKey: "debug.simulateEmptyRecordings")
        }
    }

    private static let uiTestingContainer: ModelContainer = {
        do {
            let schema = Schema([Record.self, Tag.self, AppSettings.self, RecordSpeakerSegment.self, SpeakerProfile.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])

            if !isEmptyState {
                seedTestData(in: container.mainContext)
            }
            return container
        } catch {
            fatalError("Failed to create UI testing container: \(error)")
        }
    }()

    @MainActor
    private static func seedTestData(in context: ModelContext) {
        let settings = AppSettings()
        context.insert(settings)

        let tag1 = Tag(name: "meeting")
        let tag2 = Tag(name: "important")
        let tag3 = Tag(name: "personal")
        context.insert(tag1)
        context.insert(tag2)
        context.insert(tag3)

        let record1 = Record(
            name: "Team Standup March 15",
            fileURL: nil,
            duration: 1845
        )
        record1.transcriptionText = "This is a sample transcription of the team standup meeting. We discussed the progress on the new feature and identified some blockers."
        record1.summaryText = "## Team Standup Summary\n\n- Feature development on track\n- Two blockers identified\n- Next review scheduled for Friday"
        record1.tags = [tag1, tag2]
        context.insert(record1)

        let record2 = Record(
            name: "Client Call",
            fileURL: nil,
            duration: 3600
        )
        record2.transcriptionText = "Discussion with client about project requirements and timeline adjustments."
        record2.tags = [tag1]
        context.insert(record2)

        let record3 = Record(
            name: "Voice Note",
            fileURL: nil,
            duration: 120
        )
        record3.tags = [tag3]
        context.insert(record3)

        try? context.save()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(
                    Self.isUITesting
                        ? Self.uiTestingContainer
                        : try! ModelContainer(for: Record.self, Tag.self, AppSettings.self)
                )
                .environment(\.locale, appLocale)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                Button(AppLanguage.localized("settings.ellipsis")) {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
