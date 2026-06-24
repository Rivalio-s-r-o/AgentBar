import Foundation

/// Lidský popisek burn-rate projekce. Lokalizováno (en base / cs).
public enum BurnRateLabel {
    public static func text(_ p: BurnProjection, bundle: Bundle? = nil) -> String {
        let b = bundle ?? .module
        if let tte = p.timeToExhaustion {
            if tte <= 0 { return NSLocalizedString("burn.reached", bundle: b, comment: "limit reached") }
            return String(format: NSLocalizedString("burn.exhaust", bundle: b, comment: "limit in ~X"),
                          durationString(tte))
        }
        let pct = Int((p.projectedFractionAtReset * 100).rounded())
        return String(format: NSLocalizedString("burn.projected", bundle: b, comment: "→ ~X%% by reset"), pct)
    }

    /// Numerický (nelokalizovaný) kompaktní formát doby: Xd Yh / Xh Ym / Ym.
    private static func durationString(_ s: TimeInterval) -> String {
        let total = Int(s)
        let d = total / 86400, h = (total % 86400) / 3600, m = (total % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
