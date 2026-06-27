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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)   // 최소 15분 뒤
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask, container: ModelContainer) {
        schedule()   // 다음 회차 예약
        Task { @MainActor in
            let context = ModelContext(container)
            let events = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
            // 가장 가까운 일정 있는 날(오늘 비어도 미래 일정 표시) — 포그라운드와 동일 로직, BGTask가 미래 LA를 끄지 않게.
            let shown = DayPlan.upcoming(events: events)
            if let shown {
                LiveActivityController.shared.refresh(plan: shown.plan, dayLabel: label(for: shown.day))
            } else {
                await LiveActivityController.shared.end()
            }
            #if canImport(WatchConnectivity)
            let wp = shown?.plan ?? DayPlan(events: events, day: .now)
            WatchSync.shared.send(wp.watchPayload(dayLabel: label(for: shown?.day ?? .now)))
            #endif
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { task.setTaskCompleted(success: false) }
    }

    private static func label(for day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f.string(from: day)
    }
}
