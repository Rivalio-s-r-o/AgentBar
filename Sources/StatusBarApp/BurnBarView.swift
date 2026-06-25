import SwiftUI
import StatusBarKit

/// Dvoubarevný „buffered" burn proužek (used plné + projekce světlejší + overLimit červená) pro popover.
struct BurnBarView: View {
    let bar: BurnBar
    private func color(_ l: UsageLevel) -> Color {
        switch l { case .normal: return .green; case .warning: return .orange; case .critical: return .red }
    }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12))
                if bar.projected > bar.used {
                    Rectangle().fill((bar.overLimit ? Color.red : color(bar.projectedLevel)).opacity(0.32))
                        .frame(width: w * min(1.0, bar.projected))
                }
                Rectangle().fill(color(bar.usedLevel)).frame(width: w * min(1.0, bar.used))
                if bar.overLimit {
                    Rectangle().fill(Color.red).frame(width: 3).offset(x: w - 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 7)
    }
}
