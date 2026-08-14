import Foundation
import UserNotifications

enum ReminderCalculator {
    static func nextDueDate(
        after completedAt: Date,
        scheduleType: ScheduleType,
        intervalValue: Int?,
        preservingTimeFrom timeSource: Date? = nil,
        calendar: Calendar = .current
    ) -> Date? {
        let calculatedDate: Date? = switch scheduleType {
        case .oneOff:
            nil
        case .intervalDays:
            intervalValue.flatMap { calendar.date(byAdding: .day, value: $0, to: completedAt) }
        case .calendarMonths, .preset:
            intervalValue.flatMap { calendar.date(byAdding: .month, value: $0, to: completedAt) }
        case .calendarYears:
            intervalValue.flatMap { calendar.date(byAdding: .year, value: $0, to: completedAt) }
        }

        guard let calculatedDate, let timeSource else { return calculatedDate }
        let time = calendar.dateComponents([.hour, .minute], from: timeSource)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: 0,
            of: calculatedDate
        )
    }
}

protocol ReminderNotificationScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func replaceNotifications(for reminder: ReminderItem, petName: String) async throws
    func removeNotifications(reminderID: UUID) async
}

struct LocalReminderNotificationScheduler: ReminderNotificationScheduling, @unchecked Sendable {
    private let identifierPrefix = "zoji.reminder."

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
        } catch {
            return false
        }
    }

    func replaceNotifications(for reminder: ReminderItem, petName: String) async throws {
        await removeNotifications(reminderID: reminder.id)
        guard reminder.isEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let calendar = Calendar.current
        for advanceDay in Set(reminder.advanceDays).filter({ $0 >= 0 }).sorted(by: >) {
            guard
                let alertAt = calendar.date(byAdding: .day, value: -advanceDay, to: reminder.dueAt),
                alertAt > Date()
            else { continue }

            let content = UNMutableNotificationContent()
            let localizedReminderTitle = L10n.dynamic(reminder.title)
            content.title = L10n.string("Zoji 健康提醒")
            content.body = advanceDay == 0
                ? String(
                    localized: "今天该为 \(petName) 安排：\(localizedReminderTitle)",
                    locale: L10n.locale
                )
                : String(
                    localized: "\(petName) 的“\(localizedReminderTitle)”还有 \(advanceDay) 天",
                    locale: L10n.locale
                )
            content.sound = .default
            content.userInfo = ["reminderID": reminder.id.uuidString, "petID": reminder.petID.uuidString]

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: alertAt
            )
            let request = UNNotificationRequest(
                identifier: identifier(for: reminder.id, advanceDay: advanceDay),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try await center.add(request)
        }
    }

    func removeNotifications(reminderID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let prefix = "\(identifierPrefix)\(reminderID.uuidString)."
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func identifier(for reminderID: UUID, advanceDay: Int) -> String {
        "\(identifierPrefix)\(reminderID.uuidString).\(advanceDay)"
    }
}

struct NoOpReminderNotificationScheduler: ReminderNotificationScheduling {
    func requestAuthorization() async -> Bool { true }
    func replaceNotifications(for reminder: ReminderItem, petName: String) async throws { }
    func removeNotifications(reminderID: UUID) async { }
}
