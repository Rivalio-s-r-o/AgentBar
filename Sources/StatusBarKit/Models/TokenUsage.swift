import Foundation

public struct TokenUsage: Sendable, Equatable {
    public let input: UInt
    public let output: UInt
    public let cacheWrite: UInt
    public let cacheRead: UInt
    public init(input: UInt = 0, output: UInt = 0, cacheWrite: UInt = 0, cacheRead: UInt = 0) {
        self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead
    }
    public static let zero = TokenUsage()
    public var totalTokens: UInt { input + output + cacheWrite + cacheRead }
    public static func + (a: TokenUsage, b: TokenUsage) -> TokenUsage {
        TokenUsage(input: a.input + b.input, output: a.output + b.output,
                   cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
    }
}

public struct ModelTokens: Sendable, Equatable {
    public let modelName: String
    public let tokens: TokenUsage
    public init(modelName: String, tokens: TokenUsage) { self.modelName = modelName; self.tokens = tokens }
}

public struct TodayUsage: Sendable, Equatable {
    public let perModel: [ModelTokens]
    public let estimatedCost: Decimal
    public init(perModel: [ModelTokens], estimatedCost: Decimal) {
        self.perModel = perModel; self.estimatedCost = estimatedCost
    }
    public var total: TokenUsage { perModel.reduce(.zero) { $0 + $1.tokens } }
}
