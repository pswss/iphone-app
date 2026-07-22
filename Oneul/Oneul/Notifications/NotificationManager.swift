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

    /// 전체 일정에 대해 알림 재설정.
    /// 7일 창 없이 모든 미래 알림 후보를 발화 시각순으로 모아 iOS 한도 64슬롯을 채운다 —
    /// 몇 주 앱을 안 열고 BGAppRefresh가 안 돌아도 예약된 알림이 끊기지 않는다.
    /// - 일정 1·2차 알림: 전체 미래 일정
    /// - 다가오는 시험(30일 내): 전날 저녁 8시 준비물·응원 알림
    func reschedule(for events: [ScheduleEvent]) {
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let cal = Calendar.current
        let examHorizon = cal.date(byAdding: .day, value: 30, to: now) ?? now
        struct Candidate { let id: String; let title: String; let body: String; let fire: Date; let eventStart: Date }
        var candidates: [Candidate] = []

        // 1) 일정의 1·2차 알림 — 미래 전체가 후보
        for e in events where e.start > now {
            for (i, mins) in [e.reminderMinutes, e.reminderMinutes2].enumerated() where mins >= 0 {
                let fire = e.start.addingTimeInterval(TimeInterval(-mins * 60))
                guard fire > now else { continue }
                candidates.append(Candidate(
                    id: "\(e.id.uuidString)-r\(i)",
                    title: e.title.isEmpty ? (AppLanguage.shared.isEnglish ? "Event" : "일정") : e.title,
                    body: Self.subtitle(for: e), fire: fire, eventStart: e.start))
            }
        }

        // 2) 다가오는 시험 — 전날 준비물 + 응원 (기본 20:00, 설정에서 끄기/시각 변경 가능)
        let d = UserDefaults.standard
        let examEveEnabled = d.object(forKey: "examEveEnabled") as? Bool ?? true
        let examEveMinutes = d.object(forKey: "examEveMinutes") as? Int ?? 20 * 60
        for e in events where examEveEnabled && e.examKind.isExam && e.start > now && e.start <= examHorizon {
            guard let prevDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: e.start)),
                  let fire = cal.date(bySettingHour: examEveMinutes / 60, minute: examEveMinutes % 60,
                                      second: 0, of: prevDay),
                  fire > now else { continue }
            let items = e.examKind.checklist.joined(separator: ", ")
            let en = AppLanguage.shared.isEnglish
            candidates.append(Candidate(
                id: "\(e.id.uuidString)-exam", title: en ? "Tomorrow: \(e.title)" : "내일 \(e.title)",
                body: en ? "Bring: \(items)" : "준비물: \(items)\n\(Self.cheer(for: e.start))",
                fire: fire, eventStart: e.start))
        }

        // 발화 시각순으로 64슬롯 채우기 — 가까운 알림이 항상 우선, 먼 알림부터 잘림
        for c in candidates.sorted(by: { $0.fire < $1.fire }).prefix(64) {
            add(id: c.id, title: c.title, body: c.body, at: c.fire, eventStart: c.eventStart)
        }
    }

    private func add(id: String, title: String, body: String, at fire: Date, eventStart: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive   // 집중 모드에서도 일정 알림 전달(엔타이틀먼트 필요)
        content.userInfo = ["eventStart": eventStart.timeIntervalSince1970]   // 탭 → 그 날짜로 이동
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: UNUserNotificationCenterDelegate
    //
    // 주의: 이 델리게이트들을 async 버전으로 구현하면 안 됨 — 앱 활성화 전(콜드 스타트
    // 직후·백그라운드)에 응답이 전달되면 UIKit이 async 완료 시점에 스냅샷/상태 저장을
    // 시도하다 assertion 크래시(실기기 로그: _updateStateRestorationArchiveForBackgroundEvent).
    // completionHandler 방식은 이 경로를 타지 않는다.

    /// 앱 사용 중에도 배너·사운드 표시 — 없으면 포그라운드에서 알림이 조용히 사라짐.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    /// 알림 탭 → 해당 일정 날짜로 이동.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let ts = response.notification.request.content.userInfo["eventStart"] as? TimeInterval {
            let day = Date(timeIntervalSince1970: ts)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .oneulShowDay, object: day)
            }
        }
        completionHandler()
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
