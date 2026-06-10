import AppKit
import UserNotifications

/// Sends reminders as system notifications (and/or a sound).
enum Notifier {
    private static var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard hasBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String, notify: Bool, sound: Bool) {
        if notify, hasBundle {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = .default }
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        } else if sound {
            NSSound(named: "Glass")?.play()
        }
    }
}
