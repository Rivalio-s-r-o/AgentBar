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
    private var refreshActivity: NSBackgroundActivityScheduler?

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

    private func showAbout() {
        NSApp.activate()
        let credits = NSAttributedString(
            string: "github.com/Rivalio-s-r-o/AgentBar",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor])
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "AgentBar",
            .applicationVersion: version,
            .credits: credits,
        ])
    }

    /// Naplánuje periodické obnovování přes NSBackgroundActivityScheduler (battery/thermal/Low-Power aware,
    /// OS slučuje probuzení). Vždy vytvoří ČERSTVOU instanci (stará se invaliduje) — robustní napříč
    /// pauzou/obnovou při spánku displeje bez spoléhání na re-schedule invalidované instance.
    private func startRefreshScheduler() {
        refreshActivity?.invalidate()
        let activity = NSBackgroundActivityScheduler(identifier: "cz.rivalio.statusbar.refresh")
        activity.repeats = true
        activity.interval = 60
        activity.tolerance = 20
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            // handler běží na background queue → hop na MainActor
            Task { @MainActor in
                await self?.coordinator.refreshNow(includeToday: false)
                completion(.finished)
            }
        }
        refreshActivity = activity
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
            onCheckNow: { [weak self] in Task { await self?.updates.checkNow() } },
            onAbout: { [weak self] in self?.showAbout() }
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
        startRefreshScheduler()                                               // periodické obnovování (battery-aware)
        // Pauza obnovování, když displej spí (lišta neviditelná); probuzení → znovu naplánovat + 1 refresh.
        // Swift 6: observer closure je @Sendable nonisolated → @MainActor přístup přes MainActor.assumeIsolated
        // (queue:.main běží na hlavním vlákně). Empiricky ověřeno (warnings-as-errors).
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshActivity?.invalidate() }
        }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.startRefreshScheduler()
                Task { await self.coordinator.refreshNow(includeToday: false) }
            }
        }
    }
}
