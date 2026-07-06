import Foundation
import UserNotifications

/// 일정별 로컬 알림(시작 N분 전). 서버 불필요.
/// - 포그라운드에서도 배너/사운드 표시(willPresent)
/// - 알림 탭 → 해당 일정 날짜로 이동(.oneulShowDay)
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self   // 앱 시작 시(shared 첫 접근) 연결 — 콜드 스타트 탭 응답 수신
    }

    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            self.center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// 전체 일정에 대해 알림 재설정. (iOS 64개 제한 → 가까운 일정 + 다가오는 시험만)
    /// - 가까운 일정(7일 내): 1·2차 알림 — 창을 넉넉히 잡아 앱을 며칠 안 열어도 알림 유지
    /// - 다가오는 시험(30일 내): 전날 저녁 8시 준비물·응원 알림
    func reschedule(for events: [ScheduleEvent]) {
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let cal = Calendar.current
        let soon = cal.date(byAdding: .day, value: 7, to: now) ?? now
        let examHorizon = cal.date(byAdding: .day, value: 30, to: now) ?? now
        let sorted = events.sorted { $0.start < $1.start }
        var count = 0
        let limit = 60

        // 1) 가까운 일정의 1·2차 알림 (시작 시각 순 → 한도 도달 시 먼 알림부터 잘림)
        for e in sorted where e.start > now && e.start <= soon {
            for (i, mins) in [e.reminderMinutes, e.reminderMinutes2].enumerated() where mins >= 0 {
                guard count < limit else { break }
                let fire = e.start.addingTimeInterval(TimeInterval(-mins * 60))
                guard fire > now else { continue }
                add(id: "\(e.id.uuidString)-r\(i)",
                    title: e.title.isEmpty ? (AppLanguage.shared.isEnglish ? "Event" : "일정") : e.title,
                    body: Self.subtitle(for: e), at: fire, eventStart: e.start)
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
            let en = AppLanguage.shared.isEnglish
            let body = en ? "Bring: \(items)" : "준비물: \(items)\n\(Self.cheer(for: e.start))"
            add(id: "\(e.id.uuidString)-exam", title: en ? "Tomorrow: \(e.title)" : "내일 \(e.title)",
                body: body, at: fire, eventStart: e.start)
            count += 1
        }
    }

    private func add(id: String, title: String, body: String, at fire: Date, eventStart: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        #if os(iOS)
        content.sound = AlertTone.notificationSound   // 커스텀 알림음(설정→알림음) 있으면 그걸로
        #else
        content.sound = .default
        #endif
        content.interruptionLevel = .timeSensitive   // 집중 모드에서도 일정 알림 전달(엔타이틀먼트 필요)
        content.userInfo = ["eventStart": eventStart.timeIntervalSince1970]   // 탭 → 그 날짜로 이동
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// 앱 사용 중에도 배너·사운드 표시 — 없으면 포그라운드에서 알림이 조용히 사라짐.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 알림 탭 → 해당 일정 날짜로 이동.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let ts = response.notification.request.content.userInfo["eventStart"] as? TimeInterval {
            let day = Date(timeIntervalSince1970: ts)
            await MainActor.run {
                NotificationCenter.default.post(name: .oneulShowDay, object: day)
            }
        }
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
