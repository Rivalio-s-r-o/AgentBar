import SwiftUI

/// Uvítací stav popoveru, když není připojený žádný provider (místo prázdna / dvou chybových karet).
struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "popover.welcome.title", bundle: .module))
                .font(.system(size: 13, weight: .semibold))
            Text(String(localized: "popover.welcome.body", bundle: .module))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 4)
    }
}
