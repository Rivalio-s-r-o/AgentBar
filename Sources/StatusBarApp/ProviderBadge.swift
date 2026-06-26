import SwiftUI
import StatusBarKit

/// Badge ikona providera v zaobleném čtverci (dle designu): Claude = sluneční „burst", Codex = „>_".
struct ProviderBadge: View {
    let providerId: ProviderID
    var size: CGFloat = 24

    private var accent: Color {
        providerId == .claudeCode
            ? Color(red: 0.85, green: 0.46, blue: 0.34)
            : Color(red: 0.06, green: 0.64, blue: 0.50)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).fill(accent)
            if providerId == .claudeCode {
                Canvas { ctx, sz in
                    let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                    let inner = sz.width * 0.155, outer = sz.width * 0.42
                    for i in 0..<8 {
                        let a = Double(i) * .pi / 4
                        var p = Path()
                        p.move(to: CGPoint(x: c.x + inner * cos(a), y: c.y + inner * sin(a)))
                        p.addLine(to: CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a)))
                        ctx.stroke(p, with: .color(.white),
                                   style: StrokeStyle(lineWidth: size * 0.083, lineCap: .round))
                    }
                }
            } else {
                Text(">_")
                    .font(.system(size: size * 0.46, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
    }
}
