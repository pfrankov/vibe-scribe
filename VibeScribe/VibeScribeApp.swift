//
//  VibeScribeApp.swift
//  VibeScribe
//
//  Created by Frankov Pavel on 13.04.2025.
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create the SwiftUI view for the popover
        let contentView = ContentView()
        
        // Create the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 600, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
        
        // Create the status item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "VibeScribe")
            button.action = #selector(togglePopover)
        }
        self.statusItem = statusItem
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
