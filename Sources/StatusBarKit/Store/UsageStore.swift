import Foundation
import Combine

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var providers: [ProviderID: ProviderUsage] = [:]
    public init() {}
    public func replaceAll(_ usages: [ProviderUsage]) {
        providers = Dictionary(uniqueKeysWithValues: usages.map { ($0.providerId, $0) })
    }
    public var orderedUsages: [ProviderUsage] { ProviderID.allCases.compactMap { providers[$0] } }
    public var worstPercent: Int { orderedUsages.map(\.nearestLimitPercent).max() ?? 0 }
}
