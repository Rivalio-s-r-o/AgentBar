import SwiftUI
import StatusBarKit

/// Burn proužek ve framingu „ZBÝVÁ": vyplněná část = kolik zbývá (= „% left").
/// 🟩 safe = co bezpečně zbyde do resetu (barva dle aktuálního stavu), 🟥/světlejší = co se do resetu spálí
/// (červená když to celé shoří před resetem), ⬛ šedá track = už vyčerpáno.
struct BurnBarView: View {
    let bar: BurnBar
    private func color(_ l: UsageLevel) -> Color {
        switch l { case .normal: return .green; case .warning: return .orange; case .critical: return .red }
    }
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let safeW = max(0, 1 - bar.projected)        // bezpečně zbyde do resetu
            let burnW = max(0, bar.projected - bar.used)  // spálí se do resetu
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12))   // track (zbytek vpravo = vyčerpáno)
                if burnW > 0 {
                    Rectangle().fill(bar.overLimit ? Color.red : color(bar.projectedLevel).opacity(0.45))
                        .frame(width: w * burnW).offset(x: w * safeW)
                }
                Rectangle().fill(color(bar.usedLevel)).frame(width: w * safeW)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 7)
    }
}
