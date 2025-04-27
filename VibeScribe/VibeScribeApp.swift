//
//  VibeScribeApp.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI
import AppKit
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var modelContainer: ModelContainer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let schema = Schema([
                Record.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("SwiftData ModelContainer initialized successfully.")
            
            guard let container = modelContainer else {
                fatalError("ModelContainer is nil after initialization")
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
            
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
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
