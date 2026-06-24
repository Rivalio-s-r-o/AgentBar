import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let onRequestNotificationPermission: () -> Void
    private let onAppearanceChanged: () -> Void
    private let updates: UpdateCoordinator
    private let onCheckNow: () -> Void

    init(onRequestNotificationPermission: @escaping () -> Void = {},
         onAppearanceChanged: @escaping () -> Void = {},
         updates: UpdateCoordinator,
         onCheckNow: @escaping () -> Void = {}) {
        self.onRequestNotificationPermission = onRequestNotificationPermission
        self.onAppearanceChanged = onAppearanceChanged
        self.updates = updates
        self.onCheckNow = onCheckNow
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            w.title = String(localized: "window.settings.title", bundle: .module)
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(
                rootView: SettingsView(updates: updates,
                                       onRequestNotificationPermission: onRequestNotificationPermission,
                                       onAppearanceChanged: onAppearanceChanged,
                                       onCheckNow: onCheckNow))
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
