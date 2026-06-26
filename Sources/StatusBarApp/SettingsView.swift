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
        VStack(alignment: .leading, spacing: 18) {

            // Náhled v menu baru
            SettingsSection(String(localized: "settings.preview", bundle: .module)) {
                MenuBarPreview(usages: store.orderedUsages, showUsedPercent: showUsedPercent, source: barWindowSource)
            } caption: { Text(previewCaption).font(.system(size: 11)).foregroundStyle(.tertiary) }

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
        .padding(18)
        .frame(width: 404)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var rowDivider: some View { Divider().padding(.leading, 14) }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6)
                .foregroundStyle(.tertiary).padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13.5))
                if let s = subtitle { Text(s).font(.system(size: 11)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 8)
            trailing
        }.padding(.horizontal, 14).frame(minHeight: 44)
    }
}

/// Živý náhled menu baru v Nastavení.
private struct MenuBarPreview: View {
    let usages: [ProviderUsage]
    let showUsedPercent: Bool
    let source: BarWindowSource

    private func dotColor(_ id: ProviderID) -> Color {
        id == .claudeCode ? Color(red: 0.85, green: 0.46, blue: 0.34) : Color(red: 0.06, green: 0.64, blue: 0.50)
    }
    private func levelColor(_ used: Int) -> Color {
        switch UsageLevel.level(forPercent: used) {
        case .normal: return .green; case .warning: return .orange; case .critical: return .red
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            Spacer()
            ForEach(usages.prefix(2).filter { if case .unavailable = $0.status { return false }; return true }, id: \.providerId) { u in
                let used = u.usedPercent(for: source)
                let shown = showUsedPercent ? used : max(0, 100 - used)
                HStack(spacing: 6) {
                    Circle().fill(dotColor(u.providerId)).frame(width: 6, height: 6)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: 36, height: 9)
                        Capsule().fill(levelColor(used)).frame(width: 36 * CGFloat(max(0, 100 - used)) / 100, height: 9)
                    }.frame(width: 36, height: 9)
                    Text("\(shown)%").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
            }
            Text(Date.now, format: .dateTime.hour().minute()).font(.system(size: 12)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 12).frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.17, green: 0.23, blue: 0.40),
                                            Color(red: 0.36, green: 0.29, blue: 0.55),
                                            Color(red: 0.64, green: 0.36, blue: 0.47)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
