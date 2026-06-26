import SwiftUI
import StatusBarKit

/// Timeline proužek (dle designu) — framing ZBÝVÁ, „stihneš to do resetu?".
/// Plná část = co bezpečně zbyde do resetu (barva dle PROJEKTOVANÉHO stavu),
/// šrafy = co se do resetu spálí (barva dle AKTUÁLNÍHO stavu), ryska = projektovaný stav při resetu.
struct TimelineBarView: View {
    let bar: BurnBar

    private func color(_ l: UsageLevel) -> Color {
        switch l { case .normal: return .green; case .warning: return .orange; case .critical: return .red }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let safe = max(0, 1 - bar.projected)        // bezpečně zbyde do resetu
            let burn = max(0, bar.projected - bar.used)  // spálí se do resetu
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))                              // track = vyčerpáno
                    Capsule().fill(bar.overLimit ? Color.red : color(bar.projectedLevel))     // plná = bezpečně zbyde
                        .frame(width: w * safe)
                    if burn > 0 {
                        TimelineHatch(color: bar.overLimit ? .red : color(bar.usedLevel))     // šrafy = spálí se
                            .frame(width: w * burn).offset(x: w * safe)
                    }
                }
                .clipShape(Capsule())
                // ryska projekce (mírný přesah mimo clip)
                Rectangle().fill(Color.primary).frame(width: 1.5, height: 9)
                    .offset(x: max(0, w * safe - 0.75))
            }
        }
        .frame(height: 6)
    }
}

/// Diagonální šrafování (repeating stripes) v dané barvě.
private struct TimelineHatch: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.16)))
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(color.opacity(0.85)), lineWidth: 1.2)
                x += 4
            }
        }
    }
}
