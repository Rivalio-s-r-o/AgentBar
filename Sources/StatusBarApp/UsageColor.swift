import SwiftUI
import StatusBarKit

enum UsageColor {
    static func color(forFraction f: Double) -> Color {
        switch UsageLevel.level(forPercent: Int((f * 100).rounded())) {
        case .normal: return .green; case .warning: return .orange; case .critical: return .red
        }
    }
}
