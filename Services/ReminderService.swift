import Foundation
import UserNotifications

/// Schedules/cancels the local (on-device only, no push server, no network involved at all)
/// notification behind a card's 追蹤提醒 (follow-up reminder) date. `BusinessCard.followUpDate`
/// is the single source of truth — every call here just makes the OS notification match
/// whatever that field currently says, keyed by the card's own `id` so re-scheduling or
/// cancelling always targets the right one and never leaves stale notifications behind after
/// the date is changed, cleared, or the card itself is deleted.
enum ReminderService {
    /// Must be called (and its result respected) before the first `schedule(for:)` — iOS shows
    /// the system permission prompt only once; if the user denies it, `add(_:)` silently no-ops
    /// on all iOS versions, so the reminder date would otherwise be saved but never actually
    /// fire with no indication why. Callers should check the returned Bool and let the user know
    /// if it came back false (Settings → 通知 to turn it back on).
    static func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                DispatchQueue.main.async { completion(true) }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            case .denied, .ephemeral:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private static func identifier(for cardID: UUID) -> String {
        "followup-\(cardID.uuidString)"
    }

    /// Schedules a one-time local notification at `date` for this card, replacing any reminder
    /// already scheduled for it (adding with the same identifier overwrites in place, so this
    /// never needs to cancel-then-add separately). A `date` already in the past still gets
    /// scheduled — `UNCalendarNotificationTrigger` simply won't fire it, which is harmless and
    /// keeps the caller (CardFormView) simple: it doesn't need to guard against "did the user
    /// just pick today's date after the reminder hour already passed".
    static func schedule(cardID: UUID, name: String, date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: cardID)])

        let content = UNMutableNotificationContent()
        content.title = "追蹤提醒"
        content.body = name.isEmpty ? "該聯絡這位名片聯絡人了" : "該聯絡「\(name)」了"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier(for: cardID), content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancels this card's reminder, if any — called when the user clears the follow-up date,
    /// or when the card is deleted (soft- or permanently) so it doesn't fire for a contact
    /// that's no longer in the list.
    static func cancel(cardID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: cardID)])
    }
}
