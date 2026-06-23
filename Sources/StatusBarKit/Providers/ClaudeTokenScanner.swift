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

        var byModel: [String: TokenUsage] = [:]
        if let en = FileManager.default.enumerator(at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in en where url.pathExtension == "jsonl" {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                guard let mod, mod >= dayStart else { continue }   // jen dnes upravené soubory
                guard let data = try? Data(contentsOf: url) else { continue }
                for (model, usage) in ClaudeTokenParser.sumByModel(fromJSONL: data, dayStart: dayStart, dayEnd: dayEnd) {
                    byModel[model, default: .zero] = (byModel[model] ?? .zero) + usage
                }
            }
        }
        guard !byModel.isEmpty else { return nil }
        let perModel = byModel.map { ModelTokens(modelName: $0.key, tokens: $0.value) }
            .sorted { $0.modelName < $1.modelName }
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimate(perModel))
    }
}
