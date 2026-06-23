import Foundation

public enum TokenFormatter {
    public static func compact(_ n: UInt) -> String {
        switch n {
        case 1_000_000...:
            let v = Double(n) / 1_000_000
            return String(format: "%.2fM", v)
        case 1_000...:
            return "\(n / 1000)K"
        default:
            return "\(n)"
        }
    }
    public static func money(_ d: Decimal) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 2; nf.maximumFractionDigits = 2   // zaokrouhlí na 2 místa
        nf.groupingSeparator = ""; nf.decimalSeparator = "."
        return "$" + (nf.string(from: NSDecimalNumber(decimal: d)) ?? "0.00")
    }
    public static func modelShortName(_ raw: String) -> String {
        let m = raw.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        if m.contains("codex") { return "Codex" }
        return raw
    }
}
