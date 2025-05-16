//
//  VibeScribeApp.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI
import Combine
import SwiftData
import AppKit
import ServiceManagement
import AVFoundation
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        
        requestPermissions { micGranted in
             DispatchQueue.main.async { // Ensure UI updates on main thread
                // Log permission status
                print("Microphone access: \(micGranted ? "Granted" : "Denied or Undetermined")")
                // Screen capture permission is implicitly handled by SCShareableContent.current access
                // You might want to add a check later to see if content is available,
                // which indirectly confirms permission.
             }
         }
    }
    
    func setupStatusBar() {
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Use a more visible icon - microphone symbol
            button.image = NSImage(systemSymbolName: "mic.circle.fill", accessibilityDescription: "VibeScribe")
            button.action = #selector(toggleMainWindow)
        }
        
        // Create menu for status bar item
        let menu = NSMenu()
        
        // Open/Show the main window
        menu.addItem(NSMenuItem(title: "Open", action: #selector(toggleMainWindow), keyEquivalent: "o"))
        
        // Start/Stop recording
        menu.addItem(NSMenuItem(title: "Start Recording", action: #selector(startRecording), keyEquivalent: "r"))
        
        // Add separator
        menu.addItem(NSMenuItem.separator())
        
        // Quit application
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        // Set the menu
        statusItem?.menu = menu
    }
    
    @objc func toggleMainWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func startRecording() {
        // Placeholder for recording functionality
        print("Start recording triggered from menu")
        // This would typically activate the recording functionality
    }
    
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        // Request Microphone access first
        AVCaptureDevice.requestAccess(for: .audio) { micGranted in
            guard micGranted else {
                print("Microphone access denied.")
                // Complete with mic status, screen capture prompt won't show if mic denied.
                completion(false)
                return
            }
            print("Microphone access granted.")

            // If mic granted, attempt to access shareable content to trigger Screen Capture prompt
            // This is asynchronous and doesn't block the main setup.
            if #available(macOS 12.3, *) {
                Task {
                    do {
                        // Accessing .current triggers the permission prompt if needed
                        _ = try await SCShareableContent.current
                        print("Screen capture prompt potentially shown (or permission already granted/denied).")
                        // We can't reliably check the *result* of the SC prompt here synchronously.
                        // Proceed with app setup based on mic permission.
                    } catch {
                        print("Error accessing SCShareableContent (might indicate an issue, but not necessarily denial): \(error.localizedDescription)")
                        // Proceed based on mic permission even if this fails.
                    }
                    // Call completion *after* attempting SCShareableContent access
                    // Reflecting only the mic status for now.
                    completion(true) // Mic was granted
                }
            } else {
                print("Screen Capture audio recording requires macOS 12.3 or later.")
                // Microphone granted, but screen capture not possible/prompt won't show.
                completion(true) // Mic was granted
            }
        }
    }
}

@main
struct VibeScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var modelContainer: ModelContainer?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(createModelContainer())
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(CGSize(width: 800, height: 600))
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
    
    func createModelContainer() -> ModelContainer {
        do {
            let schema = Schema([
                Record.self,
                AppSettings.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("SwiftData ModelContainer initialized successfully.")
            
            // Initialize default settings in the background
            Task {
                await initializeDefaultSettings(container: container)
            }
            
            return container
        } catch {
            print("Critical error: Could not initialize ModelContainer: \(error)")
            // Fallback to in-memory container to avoid crashing
            do {
                let schema = Schema([Record.self, AppSettings.self])
                return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            } catch {
                fatalError("Fatal error: Could not create even an in-memory ModelContainer: \(error)")
            }
        }
    }
    
    // Ensure default settings are initialized
    func initializeDefaultSettings(container: ModelContainer) async {
        do {
            let descriptor = FetchDescriptor<AppSettings>(predicate: #Predicate { $0.id == "app_settings" })
            let context = ModelContext(container)
            let existingSettings = try context.fetch(descriptor)
            
            if existingSettings.isEmpty {
                // Create default settings
                let defaultSettings = AppSettings()
                context.insert(defaultSettings)
                try context.save()
                print("Default settings initialized")
            } else {
                print("Settings already exist, no initialization needed")
            }
        } catch {
            print("Error checking/initializing default settings: \(error)")
        }
    }
}
