import AppKit
import Combine
import SwiftUI
import StatusBarKit

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let store: UsageStore
    private let prefs: PreferencesStore
    private let updates: UpdateCoordinator
    private let onRefresh: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    /// Stav otevřenosti popoveru — předáno do SwiftUI (FreshnessDot animuje jen když je otevřený).
    let popoverVisibility = PopoverVisibility()

    private let onOpenSettings: () -> Void
    init(store: UsageStore, costHistory: CostHistoryStore, prefs: PreferencesStore, updates: UpdateCoordinator,
         onClick: @escaping () -> Void, onOpenSettings: @escaping () -> Void = {}) {
        self.store = store
        self.prefs = prefs
        self.updates = updates
        self.onRefresh = onClick
        self.onOpenSettings = onOpenSettings
        super.init()
        render(store.orderedUsages)
        cancellable = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.render(self.store.orderedUsages)
            }
        }
        popover.behavior = .transient
        popover.delegate = self
        let hosting = NSHostingController(rootView:
            PopoverView(store: store, costHistory: costHistory, updates: updates, onRefresh: onClick,
                        onQuit: { NSApp.terminate(nil) }, onOpenSettings: onOpenSettings)
                .environmentObject(popoverVisibility))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
    }

    // NSPopoverDelegate: přepíná stav viditelnosti pro FreshnessDot.
    func popoverDidShow(_ notification: Notification) { popoverVisibility.isOpen = true }
    func popoverDidClose(_ notification: Notification) { popoverVisibility.isOpen = false }

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
    private func render(_ allUsages: [ProviderUsage]) {
        // 0 připojených (vše ghost) → neutrální onboarding ikona místo dat.
        let anyConnected = allUsages.contains {
            !ProviderConnectivity.isGhost(status: $0.status,
                                          isConfigured: ProviderConnectivity.isConfigured($0.providerId))
        }
        if !anyConnected && !allUsages.isEmpty {
            let img = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "AgentBar")
            img?.isTemplate = true
            statusItem.button?.attributedTitle = NSAttributedString(string: img == nil ? "AgentBar" : "")
            statusItem.button?.image = img
            let tip = NSLocalizedString("menubar.tooltip.empty", bundle: .module, comment: "")
            statusItem.button?.toolTip = tip
            statusItem.button?.setAccessibilityLabel(tip)
            return
        }
        // Ghosty se v liště nikdy nezobrazí; pak teprve volba uživatele (Oba/Claude/Codex).
        let connected = allUsages.filter {
            !ProviderConnectivity.isGhost(status: $0.status,
                                          isConfigured: ProviderConnectivity.isConfigured($0.providerId))
        }
        let usages = connected.filter { prefs.barProviders.includes($0.providerId) }
        if prefs.barStyle == .burnBar { renderBurnBar(usages); return }
        statusItem.button?.image = nil   // jiný styl → zruš případný obrázek
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
        statusItem.button?.toolTip = toolTipText(usages)
        statusItem.button?.setAccessibilityLabel(a11yLabel(usages))
    }

    /// Per-provider stavové popisky (sdílí tooltip i VoiceOver label) — pokrývá ok/degraded/unavailable.
    private func statusParts(_ usages: [ProviderUsage]) -> [String] {
        usages.map { u -> String in
            switch u.status {
            case .ok: return String(format: NSLocalizedString("menubar.tooltip.ok", bundle: .module, comment: ""), u.displayName, max(0, 100 - u.nearestLimitPercent))
            case .degraded(let m): return String(format: NSLocalizedString("menubar.tooltip.degraded", bundle: .module, comment: ""), u.displayName, m)
            case .unavailable(let m): return String(format: NSLocalizedString("menubar.tooltip.unavailable", bundle: .module, comment: ""), u.displayName, m)
            }
        }
    }

    private func toolTipText(_ usages: [ProviderUsage]) -> String { statusParts(usages).joined(separator: "\n") }

    /// Jednořádkový popisek pro VoiceOver (lišta je jinak pro odečítač neprůhledná).
    private func a11yLabel(_ usages: [ProviderUsage]) -> String {
        let parts = statusParts(usages)
        return parts.isEmpty ? "AgentBar" : "AgentBar — \(parts.joined(separator: ", "))"
    }

    private func renderBurnBar(_ usages: [ProviderUsage]) {
        let groups: [BurnBarRenderer.Group] = usages.map { u in
            if case .unavailable = u.status {
                return BurnBarRenderer.Group(dot: dotColor(u.providerId), bar: nil, percent: nil)
            }
            let bar = BurnBarBuilder.bar(for: u, source: prefs.barWindowSource, now: Date())
            let pct: Int? = bar.map { b in
                let used = Int((b.used * 100).rounded())
                return prefs.showUsedPercent ? used : max(0, 100 - used)
            }
            return BurnBarRenderer.Group(dot: dotColor(u.providerId), bar: bar, percent: pct)
        }
        if groups.isEmpty {
            statusItem.button?.image = nil
            statusItem.button?.attributedTitle = NSAttributedString(string: NSLocalizedString("menubar.fallback", bundle: .module, comment: ""))
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.button?.image = BurnBarRenderer.image(groups: groups)
        }
        statusItem.button?.toolTip = toolTipText(usages)
        statusItem.button?.setAccessibilityLabel(a11yLabel(usages))
    }
}
