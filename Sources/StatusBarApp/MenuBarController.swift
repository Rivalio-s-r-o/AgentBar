import AppKit
import Combine
import SwiftUI
import StatusBarKit

@MainActor
final class MenuBarController {
    private let store: UsageStore
    private let prefs: PreferencesStore
    private let onRefresh: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    private let onOpenSettings: () -> Void
    init(store: UsageStore, costHistory: CostHistoryStore, prefs: PreferencesStore, onClick: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void = {}) {
        self.store = store
        self.prefs = prefs
        self.onRefresh = onClick
        self.onOpenSettings = onOpenSettings
        render(store.orderedUsages)
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.render(self.store.orderedUsages)
            }
        }
        popover.behavior = .transient
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, costHistory: costHistory, onRefresh: onClick, onQuit: { NSApp.terminate(nil) },
                        onOpenSettings: onOpenSettings))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    /// Překreslí lištu po změně stylu/významu % v Nastavení.
    func applyAppearance() { render(store.orderedUsages) }

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
        let segs = MenuBarTitleBuilder.segments(for: usages,
                                                style: prefs.barStyle,
                                                showUsedPercent: prefs.showUsedPercent,
                                                source: prefs.barWindowSource)
        let title = NSMutableAttributedString()
        for (i, s) in segs.enumerated() {
            if i > 0 { title.append(NSAttributedString(string: "  ")) }
            switch s.leading {
            case .providerDot:
                title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dotColor(s.providerId), .font: NSFont.systemFont(ofSize: 9)]))
            case .levelDot:
                title.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.systemFont(ofSize: 9)]))
            case .label(let txt):
                title.append(NSAttributedString(string: "\(txt) ", attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
            case .none:
                break
            }
            if !s.text.isEmpty {
                title.append(NSAttributedString(string: s.text, attributes: [.foregroundColor: levelColor(s.level), .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)]))
            }
        }
        if segs.isEmpty { title.append(NSAttributedString(string: NSLocalizedString("menubar.fallback", bundle: .module, comment: ""))) }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = usages.map { u -> String in
            switch u.status {
            case .ok: return String(format: NSLocalizedString("menubar.tooltip.ok", bundle: .module, comment: ""), u.displayName, max(0, 100 - u.nearestLimitPercent))
            case .degraded(let m): return String(format: NSLocalizedString("menubar.tooltip.degraded", bundle: .module, comment: ""), u.displayName, m)
            case .unavailable(let m): return String(format: NSLocalizedString("menubar.tooltip.unavailable", bundle: .module, comment: ""), u.displayName, m)
            }
        }.joined(separator: "\n")
    }
}
