import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let onRequestNotificationPermission: () -> Void
    private let onAppearanceChanged: () -> Void

    init(onRequestNotificationPermission: @escaping () -> Void = {},
         onAppearanceChanged: @escaping () -> Void = {}) {
        self.onRequestNotificationPermission = onRequestNotificationPermission
        self.onAppearanceChanged = onAppearanceChanged
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = "StatusBar — Nastavení"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: SettingsView(onRequestNotificationPermission: onRequestNotificationPermission,
                                       onAppearanceChanged: onAppearanceChanged))
            w.center()
            window = w
        }
        // F1: NSApp.activate(ignoringOtherApps:) je od macOS 14 deprecated → warning.
        // Nové NSApp.activate() + orderFrontRegardless() spolehlivě vynese okno i u .accessory appky.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
