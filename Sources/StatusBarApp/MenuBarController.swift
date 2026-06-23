import AppKit
import Combine
import SwiftUI
import StatusBarKit

@MainActor
final class MenuBarController {
    private let store: UsageStore
    private let onRefresh: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    init(store: UsageStore, onClick: @escaping () -> Void) {
        self.store = store
        self.onRefresh = onClick
        render(store.orderedUsages)
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.render(self.store.orderedUsages)
            }
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 240)
        popover.contentViewController = NSHostingController(rootView:
            PopoverView(store: store, onRefresh: onClick, onQuit: { NSApp.terminate(nil) }))
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    @objc private func togglePopover() {
        guard let b = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            onRefresh()  // refresh při otevření
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func levelColor(_ l: UsageLevel) -> NSColor {
        switch l { case .normal: return .labelColor; case .warning: return .systemOrange; case .critical: return .systemRed }
    }
    private func dotColor(_ id: ProviderID) -> NSColor {
        switch id {
        case .claudeCode: return NSColor(red: 0.85, green: 0.46, blue: 0.34, alpha: 1)
        case .codex: return NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1)
        }
    }
    private func render(_ usages: [ProviderUsage]) {
        let segs = MenuBarTitleBuilder.segments(for: usages)
        let title = NSMutableAttributedString()
        for (i, s) in segs.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor(s.providerId), .font: NSFont.systemFont(ofSize: 9)]))
            title.append(NSAttributedString(string: s.text, attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
        }
        if segs.isEmpty { title.append(NSAttributedString(string: "StatusBar")) }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = usages.map { u -> String in
            switch u.status {
            case .ok: return "\(u.displayName): \(u.nearestLimitPercent) %"
            case .degraded(let m): return "\(u.displayName): ⚠︎ \(m)"
            case .unavailable(let m): return "\(u.displayName): — \(m)"
            }
        }.joined(separator: "\n")
    }
}
