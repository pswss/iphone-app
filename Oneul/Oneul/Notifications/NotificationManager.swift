import Foundation
import UserNotifications

/// 일정별 로컬 알림(시작 N분 전). 서버 불필요.
final class NotificationManager {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// 오늘 일정 전체에 대해 알림을 다시 설정(기존 것 제거 후 재등록).
    func reschedule(for events: [ScheduleEvent]) {
        center.removeAllPendingNotificationRequests()
        let now = Date()

        for event in events where event.reminderMinutes >= 0 {
            let fireDate = event.start.addingTimeInterval(TimeInterval(-event.reminderMinutes * 60))
            guard fireDate > now else { continue }   // 과거 알림은 건너뜀

            let content = UNMutableNotificationContent()
            content.title = event.title.isEmpty ? "일정" : event.title
            content.body = Self.subtitle(for: event)
            content.sound = .default

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: event.id.uuidString,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private static func subtitle(for event: ScheduleEvent) -> String {
        let lang = AppLanguage.shared
        let time = event.start.formatted(.dateTime.hour().minute().locale(lang.locale))
        if !event.location.isEmpty { return "\(time) · \(event.location)" }
        return lang.isEnglish ? "Starts \(time)" : "\(time) 시작"
    }
}
