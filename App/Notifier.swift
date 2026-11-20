import CleanKit
import UserNotifications

/// Przypomnienie o sprzątaniu jako zwykłe powiadomienie systemowe: informuje, ile można odzyskać, i nic nie kasuje.
@MainActor enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Wysyła powiadomienie, jeśli reguła na to pozwala, i zapamiętuje czas. Zwraca true, gdy wysłano.
    @discardableResult
    static func remindIfDue(reclaimable: Int64) async -> Bool {
        let d = UserDefaults.standard
        guard d.bool(forKey: "set.reminder") else { return false }
        let days = d.object(forKey: "set.reminderDays") as? Int ?? 7
        let last = d.object(forKey: "set.reminderLast") as? Date
        guard Reminder.due(last: last, intervalDays: days, reclaimable: reclaimable) else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return false }
        let c = UNMutableNotificationContent()
        c.title = "OpenCleaner"
        c.body = trf("Do odzyskania około %@. Otwórz OpenCleaner, żeby zobaczyć, co można usunąć.", Model.size(reclaimable))
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "reclaim", content: c, trigger: nil))
        d.set(Date(), forKey: "set.reminderLast")
        return true
    }
}
