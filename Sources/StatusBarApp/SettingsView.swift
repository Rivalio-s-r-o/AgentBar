import SwiftUI
import AppKit
import StatusBarKit

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updates: UpdateCoordinator
    var onRequestNotificationPermission: () -> Void = {}
    var onAppearanceChanged: () -> Void = {}
    var onAppearanceModeChanged: () -> Void = {}
    var onCheckNow: () -> Void = {}

    @AppStorage(PreferenceKeys.notificationsEnabled) private var notifsEnabled = false
    @AppStorage(PreferenceKeys.autoUpdateCheck) private var autoUpdate = true
    @AppStorage(PreferenceKeys.remainingThresholdPercent) private var threshold = 10
    @AppStorage(PreferenceKeys.barStyle) private var barStyle: MenuBarStyle = .dotPercent
    @AppStorage(PreferenceKeys.showUsedPercent) private var showUsedPercent = false
    @AppStorage(PreferenceKeys.barWindowSource) private var barWindowSource: BarWindowSource = .auto
    @AppStorage(PreferenceKeys.barProviders) private var barProviders: BarProviders = .both
    @AppStorage(PreferenceKeys.appearance) private var appearance: Appearance = .system
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var verze: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?" }

    private var updateStatusText: String {
        if updates.isChecking { return String(localized: "settings.update.checking", bundle: .module) }
        switch updates.status {
        case .upToDate(let v): return String(format: NSLocalizedString("settings.update.upToDate", bundle: .module, comment: ""), v.description)
        case .updateAvailable(let v, _): return String(format: NSLocalizedString("settings.update.available", bundle: .module, comment: ""), v.description)
        case .unknown: return String(localized: "settings.update.unknown", bundle: .module)
        }
    }

    private var previewCaption: String {
        let shows = showUsedPercent ? String(localized: "settings.used", bundle: .module) : String(localized: "settings.remaining", bundle: .module)
        return String(format: NSLocalizedString("settings.previewCaption", bundle: .module, comment: ""), barStyle.displayName, shows.lowercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {

            // Náhled v menu baru
            SettingsSection(String(localized: "settings.preview", bundle: .module)) {
                MenuBarPreview(usages: store.orderedUsages, style: barStyle, showUsedPercent: showUsedPercent,
                               source: barWindowSource, providers: barProviders)
                    .padding(6)
            } caption: { Text(previewCaption).font(.system(size: 10.5)).foregroundStyle(.tertiary) }

            // Obecné
            SettingsSection(String(localized: "settings.general", bundle: .module)) {
                SettingsRow(String(localized: "settings.launch", bundle: .module)) {
                    Toggle("", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.setEnabled(on); launchAtLogin = LaunchAtLogin.isEnabled }
                }
                rowDivider
                SettingsRow(String(localized: "settings.appearance", bundle: .module)) {
                    Picker("", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().fixedSize().onChange(of: appearance) { _, _ in onAppearanceModeChanged() }
                }
            }

            // Zobrazení v menu baru
            SettingsSection(String(localized: "settings.bar", bundle: .module)) {
                SettingsRow(String(localized: "settings.barProviders", bundle: .module)) {
                    Picker("", selection: $barProviders) {
                        ForEach(BarProviders.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().fixedSize().onChange(of: barProviders) { _, _ in onAppearanceChanged() }
                }
                rowDivider
                SettingsRow(String(localized: "settings.style", bundle: .module)) {
                    Picker("", selection: $barStyle) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().fixedSize().onChange(of: barStyle) { _, _ in onAppearanceChanged() }
                }
                rowDivider
                SettingsRow(String(localized: "settings.numberShows", bundle: .module)) {
                    Picker("", selection: $showUsedPercent) {
                        Text(String(localized: "settings.remaining", bundle: .module)).tag(false)
                        Text(String(localized: "settings.used", bundle: .module)).tag(true)
                    }.labelsHidden().pickerStyle(.segmented).fixedSize().onChange(of: showUsedPercent) { _, _ in onAppearanceChanged() }
                }
                rowDivider
                SettingsRow(String(localized: "settings.barWindow", bundle: .module)) {
                    Picker("", selection: $barWindowSource) {
                        ForEach(BarWindowSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().fixedSize().onChange(of: barWindowSource) { _, _ in onAppearanceChanged() }
                }
            }

            // Upozornění
            SettingsSection(String(localized: "settings.alerts", bundle: .module)) {
                SettingsRow(String(localized: "settings.alertToggle", bundle: .module)) {
                    Toggle("", isOn: $notifsEnabled).labelsHidden().toggleStyle(.switch)
                        .onChange(of: notifsEnabled) { _, isOn in if isOn { onRequestNotificationPermission() } }
                }
                rowDivider
                SettingsRow(String(localized: "settings.threshold", bundle: .module)) {
                    Picker("", selection: $threshold) {
                        ForEach([5, 10, 15, 20], id: \.self) { Text(String(format: NSLocalizedString("settings.percent", bundle: .module, comment: ""), $0)).tag($0) }
                    }.labelsHidden().fixedSize()
                }
            }

            // Aktualizace
            SettingsSection(String(localized: "settings.updates", bundle: .module)) {
                SettingsRow(String(localized: "settings.autoUpdate", bundle: .module)) {
                    Toggle("", isOn: $autoUpdate).labelsHidden().toggleStyle(.switch)
                }
                rowDivider
                SettingsRow(String(format: NSLocalizedString("settings.version", bundle: .module, comment: ""), verze), subtitle: updateStatusText) {
                    Button(String(localized: "settings.checkNow", bundle: .module)) { onCheckNow() }.disabled(updates.isChecking)
                }
            }
        }
        .controlSize(.small)
        .padding(14)
        .frame(width: 358)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var rowDivider: some View { Divider().padding(.leading, 12) }
}

// MARK: - Stavební bloky (styl macOS System Settings)

private struct SettingsSection<Content: View, Caption: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var caption: Caption

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder caption: () -> Caption) {
        self.title = title; self.content = content(); self.caption = caption()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.5)
                .foregroundStyle(.tertiary).padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            caption.padding(.horizontal, 4)
        }
    }
}

extension SettingsSection where Caption == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, caption: { EmptyView() })
    }
}

private struct SettingsRow<Trailing: View>: View {
    let label: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    init(_ label: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.label = label; self.subtitle = subtitle; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12.5))
                if let s = subtitle { Text(s).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 8)
            trailing
        }.padding(.horizontal, 12).frame(minHeight: 34)
    }
}

/// Živý náhled menu baru v Nastavení — vykresluje SKUTEČNÝ zvolený styl (reaguje na styl/providery/číslo/okno).
private struct MenuBarPreview: View {
    let usages: [ProviderUsage]
    let style: MenuBarStyle
    let showUsedPercent: Bool
    let source: BarWindowSource
    let providers: BarProviders

    private func dotColor(_ id: ProviderID) -> Color {
        id == .claudeCode ? Color(red: 0.85, green: 0.46, blue: 0.34) : Color(red: 0.06, green: 0.64, blue: 0.50)
    }
    // Barva textu/tečky na tmavém gradientu lišty (normal = bílá, jako labelColor v menu baru).
    private func lvlColor(_ l: UsageLevel) -> Color {
        switch l { case .normal: return .white; case .warning: return Color(.systemOrange); case .critical: return Color(.systemRed) }
    }
    // Výplň burn proužku — jako skutečný bar (green/orange/red), ne text barva.
    private func barFill(_ l: UsageLevel) -> Color {
        switch l { case .normal: return .green; case .warning: return .orange; case .critical: return .red }
    }

    private var visible: [ProviderUsage] { usages.filter { providers.includes($0.providerId) } }

    var body: some View {
        HStack(spacing: 11) {
            Spacer()
            content
            Text(Date.now, format: .dateTime.hour().minute()).font(.system(size: 11)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 11).frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.17, green: 0.23, blue: 0.40),
                                            Color(red: 0.36, green: 0.29, blue: 0.55),
                                            Color(red: 0.64, green: 0.36, blue: 0.47)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var content: some View {
        if style == .burnBar {
            ForEach(visible.prefix(2).filter { if case .unavailable = $0.status { return false }; return true }, id: \.providerId) { u in
                let used = u.usedPercent(for: source)
                let shown = showUsedPercent ? used : max(0, 100 - used)
                HStack(spacing: 6) {
                    Circle().fill(dotColor(u.providerId)).frame(width: 5, height: 5)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: 34, height: 7)
                        Capsule().fill(barFill(UsageLevel.level(forPercent: used))).frame(width: 34 * CGFloat(max(0, 100 - used)) / 100, height: 7)
                    }.frame(width: 34, height: 7)
                    Text("\(shown)%").font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
            }
        } else {
            let segs = MenuBarTitleBuilder.segments(for: visible, style: style, showUsedPercent: showUsedPercent, source: source)
            ForEach(Array(segs.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 5) {
                    switch s.leading {
                    case .providerDot: Circle().fill(dotColor(s.providerId)).frame(width: 5, height: 5)
                    case .levelDot:    Circle().fill(lvlColor(s.level)).frame(width: 5, height: 5)
                    case .label(let t): Text(t).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(lvlColor(s.level))
                    case .none:        EmptyView()
                    }
                    if !s.text.isEmpty {
                        Text(s.text).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().foregroundStyle(lvlColor(s.level))
                    }
                }
            }
        }
    }
}
