import AppKit
import StatusBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let prefs = PreferencesStore()
    private let notifier = NotificationService()
    private var lastAlerted: Set<AlertKey> = []
    private var coordinator: RefreshCoordinator!
    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        settings = SettingsWindowController(onRequestNotificationPermission: { [weak self] in
            self?.notifier.requestAuthorizationIfNeeded()
        }, onAppearanceChanged: { [weak self] in
            self?.menuBar?.applyAppearance()
        })
        menuBar = MenuBarController(store: store, prefs: prefs, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow(includeToday: true) }   // popover/refresh → skenuj today
        }, onOpenSettings: { [weak self] in
            self?.settings.show()
        })
        Task { await coordinator.refreshNow(includeToday: false) }            // start: jen limity (rychle)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.coordinator.refreshNow(includeToday: false) }   // background: jen limity
        }
    }
}
