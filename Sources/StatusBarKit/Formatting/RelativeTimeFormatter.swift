import Foundation

/// Relativní čas „před X". Lokalizováno (en base / cs).
public enum RelativeTimeFormatter {
    public static func string(from date: Date, now: Date, bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return NSLocalizedString("reltime.now", bundle: b, comment: "just now") }
        let m = s / 60
        if m < 60 { return String(format: NSLocalizedString("reltime.min", bundle: b, comment: "X minutes ago"), m) }
        let h = s / 3600
        if h < 24 { return String(format: NSLocalizedString("reltime.hour", bundle: b, comment: "X hours ago"), h) }
        return String(format: NSLocalizedString("reltime.day", bundle: b, comment: "X days ago"), s / 86400)
    }
}
