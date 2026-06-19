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

    /// 전체 일정에 대해 알림 재설정. (iOS 64개 제한 → 가까운 일정 + 다가오는 시험만)
    /// - 가까운 일정(48시간 내): 1·2차 알림
    /// - 다가오는 시험(30일 내): 전날 저녁 8시 준비물·응원 알림
    func reschedule(for events: [ScheduleEvent]) {
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let cal = Calendar.current
        let soon = cal.date(byAdding: .day, value: 2, to: now) ?? now
        let examHorizon = cal.date(byAdding: .day, value: 30, to: now) ?? now
        let sorted = events.sorted { $0.start < $1.start }
        var count = 0
        let limit = 60

        // 1) 가까운 일정의 1·2차 알림
        for e in sorted where e.start > now && e.start <= soon {
            for (i, mins) in [e.reminderMinutes, e.reminderMinutes2].enumerated() where mins >= 0 {
                guard count < limit else { break }
                let fire = e.start.addingTimeInterval(TimeInterval(-mins * 60))
                guard fire > now else { continue }
                add(id: "\(e.id.uuidString)-r\(i)",
                    title: e.title.isEmpty ? "일정" : e.title,
                    body: Self.subtitle(for: e), at: fire)
                count += 1
            }
        }

        // 2) 다가오는 시험 — 전날 20:00 준비물 + 응원
        for e in sorted where e.examKind.isExam && e.start > now && e.start <= examHorizon {
            guard count < limit else { break }
            guard let prevDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: e.start)),
                  let fire = cal.date(bySettingHour: 20, minute: 0, second: 0, of: prevDay),
                  fire > now else { continue }
            let items = e.examKind.checklist.joined(separator: ", ")
            let body = "준비물: \(items)\n\(Self.cheer(for: e.start))"
            add(id: "\(e.id.uuidString)-exam", title: "내일 \(e.title)", body: body, at: fire)
            count += 1
        }
    }

    private func add(id: String, title: String, body: String, at fire: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private static func subtitle(for event: ScheduleEvent) -> String {
        let lang = AppLanguage.shared
        let time = event.start.formatted(.dateTime.hour().minute().locale(lang.locale))
        if !event.location.isEmpty { return "\(time) · \(event.location)" }
        return lang.isEnglish ? "Starts \(time)" : "\(time) 시작"
    }

    /// 담백한 응원 한마디 (AI 티 안 나게).
    private static let cheers = [
        "푹 자고 컨디션 챙기기", "아는 것부터 차분히", "긴장보다 준비가 먼저",
        "할 수 있는 만큼만 하면 돼", "어제보다 한 문제 더"
    ]
    private static func cheer(for date: Date) -> String {
        let d = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        return cheers[d % cheers.count]
    }
}
