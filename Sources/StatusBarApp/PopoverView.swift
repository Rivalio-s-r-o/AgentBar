import SwiftUI
import AppKit
import StatusBarKit

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var costHistory: CostHistoryStore
    @ObservedObject var updates: UpdateCoordinator
    let onRefresh: () -> Void
    let onQuit: () -> Void
    var onOpenSettings: () -> Void = {}

    private var dnesCelkem: Decimal {
        store.orderedUsages.compactMap { $0.today?.estimatedCost }.reduce(Decimal(0), +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "popover.title", bundle: .module)).font(.system(size: 14, weight: .semibold))
                Spacer()
                if dnesCelkem > 0 {
                    Text(String(format: NSLocalizedString("popover.todaytotal", bundle: .module, comment: ""), TokenFormatter.money(dnesCelkem)))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.07), in: Circle())
                }.buttonStyle(.plain)
            }.padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 9)
            if case .updateAvailable(let v, let url) = updates.status {
                Divider()
                Button {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                        Text(String(format: NSLocalizedString("popover.update", bundle: .module, comment: ""), v.description))
                            .font(.caption).fontWeight(.medium)
                        Spacer()
                    }
                }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 7)
            }
            if store.orderedUsages.isEmpty {
                Divider()
                Text(String(localized: "popover.loading", bundle: .module)).foregroundStyle(.secondary).padding(16)
            } else {
                ForEach(store.orderedUsages, id: \.providerId) {
                    Divider()
                    ProviderCard(usage: $0,
                                 period: costHistory.history[$0.providerId],
                                 isComputingPeriod: costHistory.isComputing)
                }
            }
            Divider()
            HStack {
                Button(String(localized: "popover.settings", bundle: .module), action: onOpenSettings).buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "popover.quit", bundle: .module), action: onQuit).buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 312)
    }
}

/// Pulzující tečka čerstvosti dat. Animuje JEN když je popover otevřený a není zapnuté „Omezit pohyb"
/// (jinak statická tečka) — žádný Core Animation heartbeat při zavřeném popoveru / reduce-motion.
private struct FreshnessDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var vis: PopoverVisibility
    @State private var pulse = false
    var body: some View {
        Circle().fill(color).frame(width: 5, height: 5)
            .opacity(pulse ? 0.45 : 1).scaleEffect(pulse ? 0.82 : 1)
            .onAppear { apply(vis.isOpen) }
            .onChange(of: vis.isOpen) { _, open in apply(open) }
            .accessibilityHidden(true)
    }
    private func apply(_ open: Bool) {
        if open && !reduceMotion {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(nil) { pulse = false }   // okamžitě zastav + reset
        }
    }
}

private struct ProviderCard: View {
    let usage: ProviderUsage
    var period: PeriodCost? = nil
    var isComputingPeriod: Bool = false

    private var freshColor: Color {
        let age = Date().timeIntervalSince(usage.lastUpdated)
        if age < 180 { return .green }
        if age < 900 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderBadge(providerId: usage.providerId)
                Text(usage.displayName).font(.system(size: 13, weight: .semibold))
                if let p = usage.planLabel {
                    Text(p).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    FreshnessDot(color: freshColor)
                    Text(RelativeTimeFormatter.string(from: usage.lastUpdated, now: Date()))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            switch usage.status {
            case .unavailable(let m): Text(m).font(.caption).foregroundStyle(.secondary)
            case .degraded(let m): Text(m).font(.caption2).foregroundStyle(.orange); windowsList; todayRow; monthRow; linksRow
            case .ok: windowsList; todayRow; monthRow; linksRow
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var windowsList: some View {
        ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, w in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(WindowLabel.text(for: w.kind)).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(String(format: NSLocalizedString("popover.remaining", bundle: .module, comment: ""), max(0, 100 - Int((w.usedFraction*100).rounded()))))
                        .font(.system(size: 12, weight: .bold)).monospacedDigit()
                    if let r = w.resetAt {
                        Text("· \(ResetFormatter.short(until: r, now: Date()))")
                            .font(.system(size: 10.5)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
                TimelineBarView(bar: BurnBarBuilder.bar(forWindow: w, now: Date())).accessibilityHidden(true)
                paceRow(w)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func paceRow(_ w: UsageWindow) -> some View {
        let pace = PaceCalculator.pace(window: w, now: Date())
        let burn = BurnRateCalculator.project(window: w, now: Date())
        let burnText = burn.map { BurnRateLabel.text($0) }
        if pace != nil || burnText != nil {
            HStack(spacing: 5) {
                if let bt = burnText {
                    Text(bt).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                if let d = pace {
                    if burnText != nil { Text("·").font(.system(size: 10.5)).foregroundStyle(.tertiary) }
                    Text(PaceLabel.text(deltaPercent: d))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(d > 0 ? Color.orange : (d < 0 ? Color.green : Color.secondary))
                }
            }
        }
    }

    @ViewBuilder private var todayRow: some View {
        if let today = usage.today {
            Divider()
            HStack {
                Text(String(localized: "popover.today", bundle: .module)).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: NSLocalizedString("popover.today.detail", bundle: .module, comment: ""), TokenFormatter.compact(today.total.realTokens), TokenFormatter.compact(today.total.cacheTokens), TokenFormatter.money(today.estimatedCost)))
                    .font(.system(size: 12)).fontWeight(.medium)
            }
            if usage.providerId == .claudeCode, today.perModel.count > 1 {
                Text(today.perModel.map { "\(TokenFormatter.modelShortName($0.modelName)) \(TokenFormatter.compact($0.tokens.realTokens))" }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private var monthRow: some View {
        if let p = period {
            HStack {
                Text(String(format: NSLocalizedString("popover.month.compact", bundle: .module, comment: ""), TokenFormatter.compact(p.tokens.realTokens)))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(TokenFormatter.money(p.cost)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }.padding(.top, 1)
        } else if isComputingPeriod {
            Text(String(localized: "popover.computing", bundle: .module)).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var usageURL: String {
        usage.providerId == .claudeCode ? "https://claude.ai/settings/usage" : "https://platform.openai.com/usage"
    }
    private var statusURL: String {
        usage.providerId == .claudeCode ? "https://status.anthropic.com" : "https://status.openai.com"
    }
    private func linkButton(_ title: String, _ symbol: String, _ urlString: String) -> some View {
        Button { if let u = URL(string: urlString) { NSWorkspace.shared.open(u) } } label: {
            Label(title, systemImage: symbol)
        }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(.secondary)
    }
    @ViewBuilder private var linksRow: some View {
        HStack(spacing: 16) {
            linkButton(String(localized: "card.usage", bundle: .module), "chart.line.uptrend.xyaxis", usageURL)
            linkButton(String(localized: "card.status", bundle: .module), "waveform.path.ecg", statusURL)
            Spacer()
        }.padding(.top, 1)
    }
}
