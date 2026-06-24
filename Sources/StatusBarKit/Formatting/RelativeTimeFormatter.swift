import Foundation

/// Relativní čas „před X" (česky; lokalizace v0.9c).
public enum RelativeTimeFormatter {
    public static func string(from date: Date, now: Date) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "právě teď" }
        let m = s / 60
        if m < 60 { return "před \(m) min" }
        let h = s / 3600
        if h < 24 { return "před \(h) h" }
        return "před \(s / 86400) d"
    }
}
