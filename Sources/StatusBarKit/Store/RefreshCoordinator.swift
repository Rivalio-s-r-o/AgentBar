import Foundation

@MainActor
public final class RefreshCoordinator {
    private let store: UsageStore
    private let providers: [any UsageProvider]
    private var lastToday: [ProviderID: TodayUsage] = [:]
    /// Zavolá se po každém refreshi s novými daty (default no-op). App vrstva sem napojí vyhodnocení upozornění.
    public var onRefreshed: ([ProviderUsage]) -> Void = { _ in }
    public init(store: UsageStore, providers: [any UsageProvider]) { self.store = store; self.providers = providers }
    public func refreshNow(includeToday: Bool = true) async {
        var results: [ProviderUsage] = []
        await withTaskGroup(of: ProviderUsage.self) { group in
            for p in providers { group.addTask { await p.fetch(includeToday: includeToday) } }
            for await u in group { results.append(u) }
        }
        if includeToday {
            for r in results {
                if let t = r.today { lastToday[r.providerId] = t } else { lastToday.removeValue(forKey: r.providerId) }
            }
        } else {
            results = results.map { $0.with(today: lastToday[$0.providerId]) }
        }
        store.replaceAll(results)
        onRefreshed(results)
    }
}
