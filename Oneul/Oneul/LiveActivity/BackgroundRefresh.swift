#if os(iOS)
import Foundation
import SwiftData
import BackgroundTasks

/// 앱이 백그라운드일 때도 Live Activity(타임라인·다음 일정)와 워치를 주기적으로 갱신.
/// iOS가 시스템 사정에 따라 실행 시점을 정하므로(보통 수십 분 간격) 분 단위 보장은 아니지만,
/// 앱을 안 열어도 시간이 흐른 만큼 반영된다. (카운트다운 숫자 자체는 위젯이 1초마다 자동 갱신.)
enum BackgroundRefresh {
    static let taskID = "com.oneul.app.refresh"

    static func register(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task, container: container)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        // 최소 60초 뒤로 요청(가능한 한 자주). 단 BGAppRefreshTask는 iOS가 실제 실행 시점을 정하므로
        // 1분 보장은 아니고 보통 수십 분~시간 간격으로 스로틀된다.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        schedule()   // 다음 회차 예약
        Task { @MainActor in
            let context = ModelContext(container)
            let events = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
            NotificationManager.shared.reschedule(for: events)   // 앱을 안 열어도 알림 창(7일) 유지
            let shown = DayPlan.upcoming(events: events)   // 워치용
            // Live Activity는 항상 유지 — 포그라운드와 동일 규칙.
            let todayPlan = DayPlan(events: events, day: .now)
            let lang = AppLanguage.shared
            LiveActivityController.shared.refresh(plan: todayPlan, dayLabel: lang.dayLabel(for: .now))
            #if canImport(WatchConnectivity)
            let wp = shown?.plan ?? DayPlan(events: events, day: .now)
            WatchSync.shared.send(wp.watchPayload(dayLabel: lang.dayLabel(for: shown?.day ?? .now)))
            #endif
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { task.setTaskCompleted(success: false) }
    }
}
#endif
