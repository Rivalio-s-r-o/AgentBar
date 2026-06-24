import Foundation

public struct ModelPricing: Sendable, Equatable {
    public let input: Decimal      // $ / 1M
    public let output: Decimal
    public let cacheWrite: Decimal
    public let cacheRead: Decimal
    public init(input: Decimal, output: Decimal, cacheWrite: Decimal, cacheRead: Decimal) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
}

public enum PricingTable {
    public static func pricing(forModel model: String) -> ModelPricing? {
        let m = model.lowercased()
        func d(_ s: String) -> Decimal { Decimal(string: s)! }
        if m.contains("opus")   { return ModelPricing(input: d("5"),    output: d("25"), cacheWrite: d("6.25"), cacheRead: d("0.5")) }
        if m.contains("sonnet") { return ModelPricing(input: d("3"),    output: d("15"), cacheWrite: d("3.75"), cacheRead: d("0.3")) }
        if m.contains("haiku")  { return ModelPricing(input: d("1"),    output: d("5"),  cacheWrite: d("1.25"), cacheRead: d("0.1")) }
        if m.contains("codex")  { return ModelPricing(input: d("1.75"), output: d("14"), cacheWrite: d("0"),    cacheRead: d("0.175")) }
        // Pozn.: gpt-5.x větve níže nejsou aktuálně dosažitelné za běhu — CodexTokenScanner emituje model "codex"
        // (Codex info neuvádí název modelu). Ponechány pro budoucí přímé OpenAI API použití a korektnost tabulky.
        if m.contains("gpt-5.5"){ return ModelPricing(input: d("5"),    output: d("30"), cacheWrite: d("0"),    cacheRead: d("0.5")) }
        if m.contains("gpt-5")  { return ModelPricing(input: d("2.5"),  output: d("15"), cacheWrite: d("0"),    cacheRead: d("0.25")) }
        return nil
    }
}
