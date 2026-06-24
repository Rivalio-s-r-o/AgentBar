import Foundation

public struct ClaudeTokenScanner: Sendable {
    private let projectsDir: URL
    public init(projectsDir: URL? = nil) {
        self.projectsDir = projectsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    /// Sečte dnešní tokeny per model. Vrátí nil, pokud nic dnešního není.
    public func todayUsage(now: Date, calendar: Calendar = .current) -> TodayUsage? {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return rangeUsage(start: dayStart, end: dayEnd)
    }

    /// Sečte tokeny per model v rozsahu [start, end). Vrátí nil, pokud nic.
    /// Čte JEN soubory s mtime ≥ start; parser dál filtruje řádky podle timestampu do [start, end).
    public func rangeUsage(start: Date, end: Date) -> TodayUsage? {
        // 1) Posbírej URL souborů v rozsahu (mtime ≥ start) — sekvenčně (enumerator je levný).
        // F1: výsledek MUSÍ být `let` (ne `var`) — `var` zachycený v concurrentPerform = Swift 6 warning #SendableClosureCaptures.
        var collected: [URL] = []
        if let en = FileManager.default.enumerator(at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in en where url.pathExtension == "jsonl" {
                if let mod = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   mod >= start { collected.append(url) }
            }
        }
        let urls = collected
        guard !urls.isEmpty else { return nil }

        // 2) Parsuj soubory PARALELNĚ; merge přes thread-safe akumulátor (Swift 6 čistý).
        let acc = ModelTokenAccumulator()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            guard let data = try? Data(contentsOf: urls[i]) else { return }
            acc.merge(ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: start, dayEnd: end))
        }
        let byModel = acc.snapshot()

        // 3) Vyhoď 0-token modely, seřaď, spočítej reálnou cenu.
        let perModel = byModel
            .filter { $0.value.totalTokens > 0 }
            .map { ModelTokens(modelName: $0.key, tokens: $0.value) }
            .sorted { $0.modelName < $1.modelName }
        guard !perModel.isEmpty else { return nil }
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
    }
}

/// Thread-safe merge per-model tokenů z paralelního skenu (Swift 6: @unchecked Sendable + NSLock).
final class ModelTokenAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var byModel: [String: TokenUsage] = [:]
    func merge(_ partial: [String: TokenUsage]) {
        lock.lock(); defer { lock.unlock() }
        for (model, usage) in partial { byModel[model, default: .zero] = (byModel[model] ?? .zero) + usage }
    }
    func snapshot() -> [String: TokenUsage] { lock.lock(); defer { lock.unlock() }; return byModel }
}
