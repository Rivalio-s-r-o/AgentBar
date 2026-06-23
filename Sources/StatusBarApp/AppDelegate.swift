import AppKit
import StatusBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var coordinator: RefreshCoordinator!
    private var menuBar: MenuBarController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = RefreshCoordinator(store: store, providers: [ClaudeCodeCollector(), CodexCollector()])
        menuBar = MenuBarController(store: store, onClick: { [weak self] in
            Task { await self?.coordinator.refreshNow() }
        })
        Task { await coordinator.refreshNow() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.coordinator.refreshNow() }
        }
    }
}
