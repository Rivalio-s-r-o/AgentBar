import SwiftUI
import AppKit
import StatusBarKit

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var costHistory: CostHistoryStore
    let onRefresh: () -> Void
    let onQuit: () -> Void
    var onOpenSettings: () -> Void = {}

    private var dnesCelkem: Decimal {
        store.orderedUsages.compactMap { $0.today?.estimatedCost }.reduce(Decimal(0), +)
    }

    private func linkButton(_ title: String, _ urlString: String) -> some View {
        Button(title) { if let u = URL(string: urlString) { NSWorkspace.shared.open(u) } }
            .buttonStyle(.borderless).font(.caption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "popover.title", bundle: .module)).font(.headline)
                Spacer()
                if dnesCelkem > 0 {
                    Text(String(format: NSLocalizedString("popover.todaytotal", bundle: .module, comment: ""), TokenFormatter.money(dnesCelkem))).font(.caption).foregroundStyle(.secondary)
                }
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if store.orderedUsages.isEmpty {
                Text(String(localized: "popover.loading", bundle: .module)).foregroundStyle(.secondary).padding(14)
            } else {
                ForEach(store.orderedUsages, id: \.providerId) {
                    ProviderCard(usage: $0,
                                 period: costHistory.history[$0.providerId],
                                 isComputingPeriod: costHistory.isComputing)
                    Divider()
                }
            }
            if store.orderedUsages.isEmpty { Divider() }   // jediný oddělovač před odkazy; jinak ho dává ForEach za poslední kartou
            VStack(alignment: .leading, spacing: 6) {
                linkButton(String(localized: "popover.link.anthropic", bundle: .module), "https://status.anthropic.com")
                linkButton(String(localized: "popover.link.openai", bundle: .module), "https://status.openai.com")
                linkButton(String(localized: "popover.link.usageClaude", bundle: .module), "https://claude.ai/settings/usage")
                linkButton(String(localized: "popover.link.usageOpenai", bundle: .module), "https://platform.openai.com/usage")
            }.padding(.horizontal, 14).padding(.vertical, 8)
            HStack {
                Button(String(localized: "popover.settings", bundle: .module), action: onOpenSettings).buttonStyle(.borderless).font(.caption)
                Spacer()
                Button(String(localized: "popover.quit", bundle: .module), action: onQuit).buttonStyle(.borderless).font(.caption)
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }.frame(width: 320)
    }
}

private struct ProviderCard: View {
    let usage: ProviderUsage
    var period: PeriodCost? = nil
    var isComputingPeriod: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(usage.providerId == .claudeCode ? Color(red:0.85,green:0.46,blue:0.34) : Color(red:0.06,green:0.64,blue:0.50)).frame(width: 9, height: 9)
                Text(usage.displayName).fontWeight(.semibold)
                Spacer()
                if let p = usage.planLabel { Text(p).font(.caption).foregroundStyle(.secondary) }
            }
            Text(String(format: NSLocalizedString("popover.updated", bundle: .module, comment: ""), RelativeTimeFormatter.string(from: usage.lastUpdated, now: Date())))
                .font(.caption2).foregroundStyle(.tertiary)
            switch usage.status {
            case .unavailable(let m): Text(m).font(.caption).foregroundStyle(.secondary)
            case .degraded(let m): Text(m).font(.caption2).foregroundStyle(.orange); windowsList; todayRow; monthRow
            case .ok: windowsList; todayRow; monthRow
            }
        }.padding(.horizontal, 14).padding(.vertical, 11)
    }

    @ViewBuilder private var monthRow: some View {
        if let p = period {
            HStack {
                Text(String(localized: "popover.month", bundle: .module)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: NSLocalizedString("popover.month.detail", bundle: .module, comment: ""), TokenFormatter.compact(p.tokens.realTokens), TokenFormatter.money(p.cost)))
                    .font(.caption).fontWeight(.medium)
            }
            // CP2 F5: ŽÁDNÝ /měs projekční řádek — jen trailing 30denní číslo.
        } else if isComputingPeriod {
            Text(String(localized: "popover.computing", bundle: .module)).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var todayRow: some View {
        if let today = usage.today {
            Divider().padding(.vertical, 2)
            HStack {
                Text(String(localized: "popover.today", bundle: .module)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: NSLocalizedString("popover.today.detail", bundle: .module, comment: ""), TokenFormatter.compact(today.total.realTokens), TokenFormatter.compact(today.total.cacheTokens), TokenFormatter.money(today.estimatedCost)))
                    .font(.caption).fontWeight(.medium)
            }
            if usage.providerId == .claudeCode, today.perModel.count > 1 {
                Text(today.perModel.map { "\(TokenFormatter.modelShortName($0.modelName)) \(TokenFormatter.compact($0.tokens.realTokens))" }
                        .joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
    private var windowsList: some View {
        ForEach(Array(usage.windows.enumerated()), id: \.offset) { _, w in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(WindowLabel.text(for: w.kind)).font(.caption).foregroundStyle(.secondary); Spacer()
                    // ZBÝVAJÍCÍ %, ne vyčerpáno
                    Text(String(format: NSLocalizedString("popover.remaining", bundle: .module, comment: ""), max(0, 100 - Int((w.usedFraction*100).rounded())))).font(.caption).fontWeight(.semibold)
                    if let r = w.resetAt { Text("· \(ResetFormatter.short(until: r, now: Date()))").font(.caption2).foregroundStyle(.secondary) }
                }
                // Fuel-gauge: bar = kolik zbývá; barva podle nebezpečí (málo zbývá → červená)
                ProgressView(value: max(0.0, min(1.0, 1 - w.usedFraction))).tint(UsageColor.color(forFraction: w.usedFraction))
                if let d = PaceCalculator.pace(window: w, now: Date()) {
                    Text(String(format: NSLocalizedString("popover.pace", bundle: .module, comment: ""), PaceLabel.text(deltaPercent: d))).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
