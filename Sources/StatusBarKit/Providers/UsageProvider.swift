import Foundation

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch(includeToday: Bool) async -> ProviderUsage
}
