import ActivityKit
import Foundation

/// 잠금화면/다이나믹 아일랜드 Live Activity를 시작·갱신·종료.
/// 서버 없이 동작 — 앱이 떠 있을 때 갱신하고, 카운트다운/진행 바는 위젯이 스스로 굴립니다.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    private var activity: Activity<ScheduleActivityAttributes>?

    /// 오늘 일정 기준으로 Live Activity를 시작 또는 갱신.
    func refresh(plan: DayPlan, dayLabel: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // 오늘 일정이 없으면 진행 중인 Activity 종료.
        guard !plan.isEmpty else {
            Task { await end() }
            return
        }

        let state = plan.contentState()
        let content = ActivityContent(state: state, staleDate: plan.dayEnd)

        if let activity {
            Task { await activity.update(content) }
        } else {
            let attributes = ScheduleActivityAttributes(dayLabel: dayLabel)
            activity = try? Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        }
    }

    /// 진행 중인 모든 Activity 종료.
    func end() async {
        for activity in Activity<ScheduleActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }
}
