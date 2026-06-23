import Foundation

@MainActor
public final class RefreshCoordinator {
    private let store: UsageStore
    private let providers: [any UsageProvider]
    public init(store: UsageStore, providers: [any UsageProvider]) { self.store = store; self.providers = providers }
    public func refreshNow() async {
        var results: [ProviderUsage] = []
        await withTaskGroup(of: ProviderUsage.self) { group in
            for p in providers { group.addTask { await p.fetch() } }
            for await u in group { results.append(u) }
        }
        store.replaceAll(results)
    }
}
