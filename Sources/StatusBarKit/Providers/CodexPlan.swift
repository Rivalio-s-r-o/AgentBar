import Foundation

public enum CodexPlan {
    /// Mapuje `plan_type` z wham/usage na čitelný štítek. nil/"" → nil.
    public static func label(forPlanType raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "plus":       return "Plus"
        case "pro":        return "Pro"
        case "free":       return "Free"
        case "team":       return "Team"
        case "enterprise": return "Enterprise"
        default:           return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}
