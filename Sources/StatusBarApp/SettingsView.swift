import SwiftUI
import StatusBarKit

struct SettingsView: View {
    var onRequestNotificationPermission: () -> Void = {}
    var onAppearanceChanged: () -> Void = {}

    @AppStorage(PreferenceKeys.notificationsEnabled) private var notifsEnabled = false
    @AppStorage(PreferenceKeys.remainingThresholdPercent) private var threshold = 10
    @AppStorage(PreferenceKeys.barStyle) private var barStyle: MenuBarStyle = .dotPercent
    @AppStorage(PreferenceKeys.showUsedPercent) private var showUsedPercent = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var verze: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.title", bundle: .module)).font(.title3).fontWeight(.semibold)

            Toggle(String(localized: "settings.launch", bundle: .module), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LaunchAtLogin.setEnabled(on)
                    launchAtLogin = LaunchAtLogin.isEnabled   // srovnej podle reálného stavu
                }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.bar", bundle: .module)).font(.headline)
                HStack {
                    Text(String(localized: "settings.style", bundle: .module)).foregroundStyle(.secondary)
                    Picker("", selection: $barStyle) {
                        ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.labelsHidden().frame(width: 160)
                    Spacer()
                }
                .onChange(of: barStyle) { _, _ in onAppearanceChanged() }
                HStack {
                    Text(String(localized: "settings.numberShows", bundle: .module)).foregroundStyle(.secondary)
                    Picker("", selection: $showUsedPercent) {
                        Text(String(localized: "settings.remaining", bundle: .module)).tag(false)
                        Text(String(localized: "settings.used", bundle: .module)).tag(true)
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 180)
                    Spacer()
                }
                .onChange(of: showUsedPercent) { _, _ in onAppearanceChanged() }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.alerts", bundle: .module)).font(.headline)
                Toggle(String(localized: "settings.alertToggle", bundle: .module), isOn: $notifsEnabled)
                    .onChange(of: notifsEnabled) { _, isOn in
                        if isOn { onRequestNotificationPermission() }
                    }
                HStack {
                    Text(String(localized: "settings.threshold", bundle: .module)).foregroundStyle(.secondary)
                    Picker("", selection: $threshold) {
                        ForEach([5, 10, 15, 20], id: \.self) { Text(String(format: NSLocalizedString("settings.percent", bundle: .module, comment: ""), $0)).tag($0) }
                    }.labelsHidden().frame(width: 80)
                    Spacer()
                }
            }

            Spacer()
            HStack { Spacer(); Text(String(format: NSLocalizedString("settings.version", bundle: .module, comment: ""), verze)).font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(20)
        .frame(width: 360, height: 360)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
