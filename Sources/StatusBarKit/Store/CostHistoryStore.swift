// Sources/StatusBarKit/Store/CostHistoryStore.swift
import Foundation
import Combine

/// Drží 30denní cenu per provider. Compute běží přes injektovaný async provider
/// (v appce off-main přes Task.detached), throttlovaně (staleInterval). MIMO rychlou collector cestu.
@MainActor
public final class CostHistoryStore: ObservableObject {
    @Published public private(set) var history: [ProviderID: PeriodCost] = [:]
    @Published public private(set) var isComputing = false
    public private(set) var lastComputed: Date?

    private let staleInterval: TimeInterval
    private let provider: @Sendable (Date) async -> [ProviderID: PeriodCost]

    public init(staleInterval: TimeInterval = 6 * 3600,
                provider: @escaping @Sendable (Date) async -> [ProviderID: PeriodCost]) {
        self.staleInterval = staleInterval
        self.provider = provider
    }

    /// Throttle: nepočítat když právě počítá nebo když je poslední výpočet čerstvý.
    public func shouldRefresh(now: Date) -> Bool {
        guard !isComputing else { return false }
        if let last = lastComputed, now.timeIntervalSince(last) < staleInterval { return false }
        return true
    }

    /// Awaitable výpočet (pro testy i interně). Respektuje throttle.
    public func refresh(now: Date) async {
        guard shouldRefresh(now: now) else { return }
        // POZN. (F4): `isComputing = true` MUSÍ být nastaveno SYNCHRONNĚ před prvním `await`.
        // Na @MainActor tím druhý souběžný refreshIfStale (start + popover-open) uvidí isComputing==true
        // ve svém shouldRefresh a vrátí se → žádný dvojitý compute. Nepřehazovat pořadí.
        isComputing = true
        let h = await provider(now)
        history = h
        lastComputed = now
        isComputing = false
    }

    /// Fire-and-forget pro app (start / popover-open).
    public func refreshIfStale(now: Date = Date()) {
        Task { await refresh(now: now) }
    }
}
