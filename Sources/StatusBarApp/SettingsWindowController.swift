import AppKit
import SwiftUI
import StatusBarKit

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: UsageStore
    private let updates: UpdateCoordinator
    private let onRequestNotificationPermission: () -> Void
    private let onAppearanceChanged: () -> Void
    private let onAppearanceModeChanged: () -> Void
    private let onCheckNow: () -> Void

    init(store: UsageStore,
         updates: UpdateCoordinator,
         onRequestNotificationPermission: @escaping () -> Void = {},
         onAppearanceChanged: @escaping () -> Void = {},
         onAppearanceModeChanged: @escaping () -> Void = {},
         onCheckNow: @escaping () -> Void = {}) {
        self.store = store
        self.updates = updates
        self.onRequestNotificationPermission = onRequestNotificationPermission
        self.onAppearanceChanged = onAppearanceChanged
        self.onAppearanceModeChanged = onAppearanceModeChanged
        self.onCheckNow = onCheckNow
    }

    func show() {
        if window == nil {
            let host = NSHostingController(
                rootView: SettingsView(store: store, updates: updates,
                                       onRequestNotificationPermission: onRequestNotificationPermission,
                                       onAppearanceChanged: onAppearanceChanged,
                                       onAppearanceModeChanged: onAppearanceModeChanged,
                                       onCheckNow: onCheckNow))
            host.sizingOptions = .preferredContentSize
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.title = String(localized: "window.settings.title", bundle: .module)
            w.isReleasedWhenClosed = false
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
