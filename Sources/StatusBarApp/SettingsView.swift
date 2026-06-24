import SwiftUI
import StatusBarKit

struct SettingsView: View {
    var onRequestNotificationPermission: () -> Void = {}

    @AppStorage(PreferenceKeys.notificationsEnabled) private var notifsEnabled = false
    @AppStorage(PreferenceKeys.remainingThresholdPercent) private var threshold = 10
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var verze: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nastavení").font(.title3).fontWeight(.semibold)

            Toggle("Spouštět při přihlášení", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    LaunchAtLogin.setEnabled(on)
                    launchAtLogin = LaunchAtLogin.isEnabled   // srovnej podle reálného stavu
                }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Upozornění").font(.headline)
                Toggle("Upozornit, když klesnou zbývající limity", isOn: $notifsEnabled)
                    .onChange(of: notifsEnabled) { _, isOn in
                        if isOn { onRequestNotificationPermission() }
                    }
                HStack {
                    Text("Práh (zbývá ≤)").foregroundStyle(.secondary)
                    Picker("", selection: $threshold) {
                        ForEach([5, 10, 15, 20], id: \.self) { Text("\($0) %").tag($0) }
                    }.labelsHidden().frame(width: 80)
                    Spacer()
                }
            }

            Spacer()
            HStack { Spacer(); Text("StatusBar \(verze)").font(.caption2).foregroundStyle(.tertiary) }
        }
        .padding(20)
        .frame(width: 360, height: 260)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
