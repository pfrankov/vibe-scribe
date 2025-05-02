//
//  VibeScribeApp.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI
import AppKit
import SwiftData
import AVFoundation
import ScreenCaptureKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var modelContainer: ModelContainer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions { micGranted in
             DispatchQueue.main.async { // Ensure UI updates on main thread
                // Original setup logic is now in setupApp()
                self.setupApp()
                // Log permission status
                print("Microphone access: \(micGranted ? "Granted" : "Denied or Undetermined")")
                // Screen capture permission is implicitly handled by SCShareableContent.current access
                // You might want to add a check later to see if content is available,
                // which indirectly confirms permission.
             }
         }
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

    func setupApp() {
        do {
            let schema = Schema([
                Record.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("SwiftData ModelContainer initialized successfully.")
            
            guard let container = modelContainer else {
                print("Error: ModelContainer is nil after initialization")
                return
            }
            
            let contentView = ContentView()
                .modelContainer(container)

            let popover = NSPopover()
            popover.contentSize = NSSize(width: 600, height: 500)
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: contentView)
            self.popover = popover
            
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem.button {
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VibeScribe")
                button.action = #selector(togglePopover)
            }
            self.statusItem = statusItem
            
            print("App UI setup complete.")
            
        } catch {
            print("Could not complete app setup: \(error)")
        }
    }
    
    @objc func togglePopover() {
        if let button = statusItem?.button, let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

@main
struct VibeScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
