import AppKit
import SwiftUI

/// Capture and Split live in real windows — presenting sheets inside a
/// MenuBarExtra panel breaks the panel (sheet re-present on reopen, dismiss
/// kills the popup).
@MainActor
final class CaptureWindowController {
    static let shared = CaptureWindowController()
    private var window: NSWindow?

    func show(store: LayoutStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Capture Window Layout"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CaptureView(store: store, onClose: { [weak self] in
            self?.window?.orderOut(nil)
        }))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class SplitWindowController {
    static let shared = SplitWindowController()
    private var window: NSWindow?

    func show(store: LayoutStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Quick Split"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SplitBuilderView(store: store, onClose: { [weak self] in
            self?.window?.orderOut(nil)
        }))
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
