import Foundation

public struct CodexTokenScanner: Sendable {
    private let sessionsDir: URL
    private let maxFilesToScan: Int
    public init(sessionsDir: URL? = nil, maxFilesToScan: Int = 50) {
        self.sessionsDir = sessionsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        self.maxFilesToScan = maxFilesToScan
    }

    /// Sečte dnešní Codex tokeny (finální total per dnešní soubor). Nil, pokud nic.
    public func todayUsage(now: Date, calendar: Calendar = .current) -> TodayUsage? {
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        return rangeUsage(start: dayStart, end: dayEnd)
    }

    /// Sečte Codex tokeny přes session soubory s mtime v [start, end). Finální `lastTotal` per soubor.
    /// POZN. (R5, akceptováno): kumulativní total → session přes hranici okna přičte i tokeny mimo rozsah.
    public func rangeUsage(start: Date, end: Date) -> TodayUsage? {
        guard let en = FileManager.default.enumerator(at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               m >= start, m < end {
                files.append((url, m))
            }
        }
        let urls = files.sorted(by: { $0.1 > $1.1 }).prefix(maxFilesToScan).map(\.0)
        guard !urls.isEmpty else { return nil }

        let acc = TokenSumAccumulator()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            guard let data = try? Data(contentsOf: urls[i]),
                  let t = CodexTokenParser.lastTotal(fromJSONL: data) else { return }
            acc.add(t)
        }
        let (sum, any) = acc.snapshot()
        guard any else { return nil }
        let perModel = [ModelTokens(modelName: "codex", tokens: sum)]
        return TodayUsage(perModel: perModel, estimatedCost: PricingEstimator.estimateReal(perModel))
    }
}

/// Thread-safe součet TokenUsage z paralelního skenu.
final class TokenSumAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var sum = TokenUsage.zero
    private var any = false
    func add(_ t: TokenUsage) { lock.lock(); sum = sum + t; any = true; lock.unlock() }
    func snapshot() -> (TokenUsage, Bool) { lock.lock(); defer { lock.unlock() }; return (sum, any) }
}
