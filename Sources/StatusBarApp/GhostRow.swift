import SwiftUI
import StatusBarKit

/// Malý ztlumený řádek nepřipojeného providera (awareness, že je podporovaný, + „Připojit").
struct GhostRow: View {
    let providerId: ProviderID
    let displayName: String
    var onConnect: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            ProviderBadge(providerId: providerId).opacity(0.4).grayscale(1).accessibilityHidden(true)
            Text(displayName).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text("· \(String(localized: "provider.notconnected", bundle: .module))")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Button(String(localized: "provider.connect", bundle: .module), action: onConnect)
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.tint)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}
