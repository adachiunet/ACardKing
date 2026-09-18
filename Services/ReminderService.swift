import Foundation
import UserNotifications

/// Schedules/cancels the local (on-device only, no push server, no network involved at all)
/// notifications behind a card's 追蹤提醒 tasks (`BusinessCard.followUpTasks`). Each task gets
/// its own notification, keyed by `cardID` + the task's own `id`, so adding, completing, or
/// deleting one task never disturbs another task's notification — the whole point of moving from
/// a single `followUpDate` to a list.
enum ReminderService {
    /// Must be called (and its result respected) before the first `schedule(...)` — iOS shows
    /// the system permission prompt only once; if the user denies it, notifications silently
    /// no-op on all iOS versions, so a task would otherwise be saved but never actually fire with
    /// no indication why. Callers should check the returned Bool and let the user know if it
    /// came back false (Settings → 通知 to turn it back on).
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

    private static func identifier(cardID: UUID, taskID: UUID) -> String {
        "followup-\(cardID.uuidString)-\(taskID.uuidString)"
    }

    /// The identifier this service used back when a card could only ever have ONE follow-up
    /// date (before `FollowUpTask`). Only referenced by `cancelLegacy` below, which the app's
    /// one-time startup migration uses to clean up a notification scheduled under the old naming
    /// scheme before re-scheduling it under the new per-task one — nothing else should ever use
    /// this format again.
    private static func legacyIdentifier(cardID: UUID) -> String {
        "followup-\(cardID.uuidString)"
    }

    /// Cancels a notification scheduled under the pre-`FollowUpTask` single-per-card identifier.
    /// Called exactly once per card by `CardKingApp.migrateLegacyFollowUpDates` — an old
    /// installed build may have left one of these pending, and since the new code never looks
    /// for that identifier again, it would otherwise linger forever as an orphaned notification.
    static func cancelLegacy(cardID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [legacyIdentifier(cardID: cardID)])
    }

    /// Schedules (or replaces, if one already exists for this task) the local notification for
    /// ONE follow-up task. A completed task is never scheduled — pass it here only to make sure
    /// any previously-scheduled notification for it gets cancelled instead (same effect as
    /// calling `cancel` directly).
    static func schedule(cardID: UUID, name: String, task: FollowUpTask) {
        guard !task.isCompleted else {
            cancel(cardID: cardID, taskID: task.id)
            return
        }
        let center = UNUserNotificationCenter.current()
        let identifier = identifier(cardID: cardID, taskID: task.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "追蹤提醒"
        let who = name.isEmpty ? "這位名片聯絡人" : "「\(name)」"
        content.body = task.note.isEmpty ? "該聯絡\(who)了" : "\(who):\(task.note)"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: task.dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// Cancels one task's notification — called when that task is deleted, marked complete, or
    /// its card is deleted.
    static func cancel(cardID: UUID, taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(cardID: cardID, taskID: taskID)])
    }

    /// Re-syncs every task's notification for a card in one call — schedules the ones that
    /// aren't done yet, cancels the ones that are. Call this after any edit to a card's
    /// `followUpTasks` (add/edit/complete/delete) so the OS notification set can never drift
    /// out of sync with what's actually on the card.
    static func syncAll(cardID: UUID, name: String, tasks: [FollowUpTask]) {
        for task in tasks {
            schedule(cardID: cardID, name: name, task: task)
        }
    }

    /// Cancels every one of a card's task notifications by id — used when the card itself is
    /// deleted (soft or permanent) or is being cleared of all follow-ups (e.g. marked as 我的
    /// 名片, which never carries any).
    static func cancelAll(cardID: UUID, taskIDs: [UUID]) {
        guard !taskIDs.isEmpty else { return }
        let identifiers = taskIDs.map { identifier(cardID: cardID, taskID: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
