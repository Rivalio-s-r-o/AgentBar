import Foundation

public enum ClaudePlan {
    /// Mapuje `subscriptionType` z Keychainu na čitelný štítek. nil/"" → nil.
    public static func label(forSubscriptionType raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "max":        return "Max"
        case "pro":        return "Pro"
        case "free":       return "Free"
        case "team":       return "Team"
        case "enterprise": return "Enterprise"
        default:           return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}
