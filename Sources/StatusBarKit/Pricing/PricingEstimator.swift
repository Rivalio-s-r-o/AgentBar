import Foundation

public enum PricingEstimator {
    public static func estimate(_ tokens: TokenUsage, model: String) -> Decimal {
        guard let p = PricingTable.pricing(forModel: model) else { return 0 }
        let perMillion = Decimal(1_000_000)
        func part(_ count: UInt, _ price: Decimal) -> Decimal { (Decimal(count) / perMillion) * price }
        return part(tokens.input, p.input) + part(tokens.output, p.output)
             + part(tokens.cacheWrite, p.cacheWrite) + part(tokens.cacheRead, p.cacheRead)
    }
    public static func estimate(_ perModel: [ModelTokens]) -> Decimal {
        perModel.reduce(Decimal(0)) { $0 + estimate($1.tokens, model: $1.modelName) }
    }
}
