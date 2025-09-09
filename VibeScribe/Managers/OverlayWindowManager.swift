import AppKit
import SwiftUI

@MainActor
final class OverlayWindowManager: ObservableObject {
    static let shared = OverlayWindowManager()

    private var panel: NSPanel?

    func show(@ViewBuilder content: () -> AnyView,
              size: NSSize? = nil,
              at position: NSPoint? = nil) {
        if panel == nil {
            let style: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView]
            let initialSize = size ?? NSSize(width: 100, height: 100)
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: initialSize),
                            styleMask: style,
                            backing: .buffered,
                            defer: false)
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.backgroundColor = .clear
            p.isOpaque = false
            // Use system window shadow (follows non-opaque window shape)
            p.hasShadow = true
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.standardWindowButton(.closeButton)?.isHidden = true
            panel = p
        }

        guard let panel else { return }

        let hosting = NSHostingController(rootView: content())
        hosting.view.wantsLayer = true
        // Clip content to rounded shape; the window shadow comes from AppKit
        hosting.view.layer?.masksToBounds = true
        hosting.view.layer?.cornerRadius = 22
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hosting

        // Round the frame view as well so the system window shadow follows the shape
        if let frameView = panel.contentView?.superview {
            frameView.wantsLayer = true
            frameView.layer?.masksToBounds = true
            frameView.layer?.cornerRadius = 22
        }

        // Auto-size the panel to the SwiftUI view's fitting size unless a fixed size is provided
        let desiredSize: NSSize
        if let size { desiredSize = size } else {
            hosting.view.layoutSubtreeIfNeeded()
            let fit = hosting.view.fittingSize
            // Provide a sensible minimum in case fitting size is zero during first pass
            desiredSize = NSSize(width: max(fit.width, 320), height: max(fit.height, 120))
        }
        panel.setFrame(NSRect(origin: panel.frame.origin, size: desiredSize), display: true)

        if let position {
            panel.setFrameOrigin(position)
        } else {
            // Always place near the top-right corner when showing (explicit request)
            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                let marginX: CGFloat = 20
                let marginY: CGFloat = 50
                let x = frame.maxX - desiredSize.width - marginX
                let y = frame.maxY - desiredSize.height - marginY
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: false)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    func bringToFront() {
        guard let panel else { return }
        panel.orderFrontRegardless()
    }

    // MARK: - Standard system alert sized to overlay
    func presentDiscardConfirm(onDiscard: @escaping () -> Void,
                               onCancel: @escaping () -> Void) {
        guard let base = panel else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard recording?"
        alert.informativeText = "This will stop and delete the current recording."
        // Standard button order (right-to-left): default on right, Cancel on left
        alert.addButton(withTitle: "Discard") // first button = rightmost
        alert.addButton(withTitle: "Cancel")  // second button = leftmost
        alert.buttons.first?.hasDestructiveAction = true
        // Show as app-modal (not a sheet) to avoid dimming the overlay window
        // and ensure it floats above our non-activating panel.
        let alertWindow = alert.window
        alertWindow.level = NSWindow.Level(rawValue: base.level.rawValue + 1)
        alertWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            onDiscard()
        } else {
            onCancel()
        }
    }
}
