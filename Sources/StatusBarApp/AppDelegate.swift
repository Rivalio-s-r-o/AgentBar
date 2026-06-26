import AppKit
import StatusBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let costHistory: CostHistoryStore
    private let prefs = PreferencesStore()
    private let notifier = NotificationService()
    private var lastAlerted: Set<AlertKey> = []
    private var coordinator: RefreshCoordinator!
    private var updates: UpdateCoordinator!
    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController!
    private var timer: Timer?

    override init() {
        let claudeScanner = ClaudeTokenScanner()
        let codexScanner = CodexTokenScanner(maxFilesToScan: 1000)   // CP2 F1: backstop cap; mtime-rozsah už filtruje 30 dní
        costHistory = CostHistoryStore(provider: { now in
            let start = now.addingTimeInterval(-30 * 86400)
            return await Task.detached(priority: .utility) {
                var out: [ProviderID: PeriodCost] = [:]
                if let c = claudeScanner.rangeUsage(start: start, end: now) {
                    out[.claudeCode] = PeriodCost(tokens: c.total, cost: c.estimatedCost)
                }
                if let x = codexScanner.rangeUsage(start: start, end: now) {
                    out[.codex] = PeriodCost(tokens: x.total, cost: x.estimatedCost)
                }
                return out
            }.value
        })
        super.init()
    }

    private func applyAppearance() {
        switch prefs.appearance {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        updates = UpdateCoordinator(prefs: prefs)
        coordinator = RefreshCoordinator(store: store, providers: [
            ClaudeCodeCollector(liveSource: LiveClaudeUsageSource()),
            CodexCollector(liveSource: LiveCodexUsageSource()),
        ])
        coordinator.onRefreshed = { [weak self] usages in
            guard let self, self.prefs.notificationsEnabled else { return }
            let (toFire, newState) = AlertEvaluator.evaluate(
                usages: usages,
                thresholdPercent: self.prefs.remainingThresholdPercent,
                alreadyAlerted: self.lastAlerted)
            self.lastAlerted = newState
            self.notifier.post(toFire)
        }
        settings = SettingsWindowController(
            store: store,
            updates: updates,
            onRequestNotificationPermission: { [weak self] in
                self?.notifier.requestAuthorizationIfNeeded()
            },
            onAppearanceChanged: { [weak self] in
                self?.menuBar?.applyAppearance()
            },
            onAppearanceModeChanged: { [weak self] in
                self?.applyAppearance()
            },
            onCheckNow: { [weak self] in Task { await self?.updates.checkNow() } }
        )
        menuBar = MenuBarController(store: store, costHistory: costHistory, prefs: prefs, updates: updates,
            onClick: { [weak self] in
                guard let self else { return }
                Task { await self.coordinator.refreshNow(includeToday: true) }   // today (rychlé)
                self.costHistory.refreshIfStale()                                 // 30 dní (throttle 6h, off-main)
                Task { await self.updates.checkIfDue() }
            },
            onOpenSettings: { [weak self] in
                self?.settings.show()
            })
        Task { await coordinator.refreshNow(includeToday: false) }            // start: jen limity
        costHistory.refreshIfStale()                                          // start: nachystej 30denní data
        Task { await updates.checkIfDue() }                                   // start: zkontroluj aktualizace
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.coordinator.refreshNow(includeToday: false) }   // 60s: jen limity — 30denní cenu NEVOLÁ
        }
    }
}
