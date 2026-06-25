import AppKit
import StatusBarKit

enum BurnBarRenderer {
    struct Group { let dot: NSColor; let bar: BurnBar?; let percent: Int? }

    private static func hue(_ level: UsageLevel) -> NSColor {
        switch level {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    static func image(groups: [Group]) -> NSImage {
        let H: CGFloat = 18, dotR: CGFloat = 3
        let barW: CGFloat = 52, barH: CGFloat = 9, barR: CGFloat = 3
        let gap1: CGFloat = 5, gap2: CGFloat = 4, groupGap: CGFloat = 12, pad: CGFloat = 2
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        func pctString(_ g: Group) -> String { g.percent.map { "\($0)%" } ?? "—" }
        func textWidth(_ g: Group) -> CGFloat { (pctString(g) as NSString).size(withAttributes: [.font: font]).width }
        func groupWidth(_ g: Group) -> CGFloat { dotR*2 + gap1 + barW + gap2 + textWidth(g) }
        let total = pad*2 + groups.map(groupWidth).reduce(0, +) + groupGap*CGFloat(max(0, groups.count - 1))

        let img = NSImage(size: NSSize(width: max(total, 1), height: H), flipped: false) { _ in
            var x = pad
            for (i, g) in groups.enumerated() {
                if i > 0 { x += groupGap }
                let midY = H/2
                // dot
                let dotRect = NSRect(x: x, y: midY - dotR, width: dotR*2, height: dotR*2)
                (g.bar == nil ? g.dot.withAlphaComponent(0.4) : g.dot).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
                x += dotR*2 + gap1
                // bar
                let barRect = NSRect(x: x, y: midY - barH/2, width: barW, height: barH)
                let track = NSBezierPath(roundedRect: barRect, xRadius: barR, yRadius: barR)
                if let bar = g.bar {
                    NSColor.labelColor.withAlphaComponent(0.14).setFill(); track.fill()
                    NSGraphicsContext.saveGraphicsState(); track.addClip()
                    if bar.projected > bar.used {
                        let pr = NSRect(x: barRect.minX + barW*CGFloat(bar.used), y: barRect.minY,
                                        width: barW*CGFloat(bar.projected - bar.used), height: barH)
                        (bar.overLimit ? NSColor.systemRed.withAlphaComponent(0.42) : hue(bar.level).withAlphaComponent(0.38)).setFill()
                        NSBezierPath(rect: pr).fill()
                    }
                    let ur = NSRect(x: barRect.minX, y: barRect.minY, width: barW*CGFloat(min(1.0, bar.used)), height: barH)
                    hue(bar.level).setFill(); NSBezierPath(rect: ur).fill()
                    if bar.overLimit {
                        let cap = NSRect(x: barRect.maxX - 3, y: barRect.minY, width: 3, height: barH)
                        NSColor.systemRed.setFill(); NSBezierPath(rect: cap).fill()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    hue(bar.level).withAlphaComponent(0.55).setStroke()
                    let border = NSBezierPath(roundedRect: barRect.insetBy(dx: 0.3, dy: 0.3), xRadius: barR, yRadius: barR)
                    border.lineWidth = 0.6; border.stroke()
                } else {
                    NSColor.labelColor.withAlphaComponent(0.10).setFill(); track.fill()
                }
                x += barW + gap2
                // pct
                let pct = pctString(g) as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
                let sz = pct.size(withAttributes: attrs)
                pct.draw(at: NSPoint(x: x, y: midY - sz.height/2), withAttributes: attrs)
                x += sz.width
            }
            return true
        }
        img.isTemplate = false
        return img
    }
}
