import Foundation

/// Tempo čerpání okna: vyčerpáno% − uplynulo% (signed). Kladné = rychleji než lineárně (napřed), záporné = pomaleji (pozadu).
public enum PaceCalculator {
    public static func pace(window: UsageWindow, now: Date) -> Int? {
        guard let reset = window.resetAt, reset > now else { return nil }
        let duration: TimeInterval = window.kind == .rolling5h ? 5 * 3600 : 7 * 24 * 3600
        let start = reset.addingTimeInterval(-duration)
        let elapsedFraction = min(1, max(0, now.timeIntervalSince(start) / duration))
        return Int(((window.usedFraction - elapsedFraction) * 100).rounded())
    }
}

/// Lidský popisek pace. Lokalizováno.
public enum PaceLabel {
    public static func text(deltaPercent d: Int, bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        if d > 0 { return String(format: NSLocalizedString("pace.ahead", bundle: b, comment: "X % ahead"), d) }
        if d < 0 { return String(format: NSLocalizedString("pace.behind", bundle: b, comment: "X % behind"), -d) }
        return NSLocalizedString("pace.onpace", bundle: b, comment: "on pace")
    }
}
