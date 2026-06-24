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
        var byModel: [String: TokenUsage] = [:]
        if let en = FileManager.default.enumerator(at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in en where url.pathExtension == "jsonl" {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                guard let mod, mod >= start else { continue }   // soubory upravené v rozsahu
                guard let data = try? Data(contentsOf: url) else { continue }
                for (model, usage) in ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: start, dayEnd: end) {
                    byModel[model, default: .zero] = (byModel[model] ?? .zero) + usage
                }
            }
        }
        // Vyhoď modely s 0 tokeny (např. "<synthetic>") — nepatří do rozpadu ani součtu.
        let perModel = byModel
            .filter { $0.value.totalTokens > 0 }
            .map { ModelTokens(modelName: $0.key, tokens: $0.value) }
            .sorted { $0.modelName < $1.modelName }
        guard !perModel.isEmpty else { return nil }
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
    }
}
