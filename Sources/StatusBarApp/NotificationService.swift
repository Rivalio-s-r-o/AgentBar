import Foundation
import UserNotifications
import StatusBarKit

@MainActor
final class NotificationService {
    // lazy: UNUserNotificationCenter.current() se dotkneme až při prvním použití (po opt-inu),
    // nikdy ne při startu appky a nikdy v testech.
    private lazy var center = UNUserNotificationCenter.current()

    // POZN. (F4): NEvnořovat getNotificationSettings { … center … } — jeho @Sendable completion
    // běží mimo main actor a sáhnutí na @MainActor `center` by pod Swift 6 neprošlo kompilací.
    // requestAuthorization už-rozhodnuté NEpromptuje znovu, takže ho lze volat přímo.
    func requestAuthorizationIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil else { return }   // bez bundlu (raw binár) notifikace neexistují
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ events: [AlertEvent]) {
        guard Bundle.main.bundleIdentifier != nil, !events.isEmpty else { return }
        for e in events {
            let content = UNMutableNotificationContent()
            content.title = "\(e.providerDisplayName) — \(e.windowLabel)"
            var body = "Zbývá \(e.remainingPercent) %"
            if let r = e.resetAt { body += " · reset za \(ResetFormatter.short(until: r, now: Date()))" }
            content.body = body
            content.sound = .default
            let id = "\(e.providerDisplayName)|\(e.windowLabel)"   // stabilní per okno → re-fire nahrazuje
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
