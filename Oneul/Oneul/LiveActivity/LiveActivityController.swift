import ActivityKit
import Foundation
import Observation

/// 잠금화면/다이나믹 아일랜드 Live Activity를 시작·갱신·종료.
/// 서버 없이 동작 — 앱이 떠 있을 때 갱신하고, 카운트다운/진행 바는 위젯이 스스로 굴립니다.
@Observable
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    /// 마지막 시작/갱신 시도 결과 — 설정의 진단 표시용(왜 안 뜨는지 그대로 보여줌).
    var status = "아직 시도 안 함 — 오늘 탭을 열거나 아래 버튼을 눌러 보세요."

    private var activity: Activity<ScheduleActivityAttributes>?

    /// 오늘(또는 다가오는) 일정 기준으로 Live Activity를 시작 또는 갱신.
    func refresh(plan: DayPlan, dayLabel: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "⚠️ '실시간 활동'이 꺼져 있어요 — 설정 → Oneul → 실시간 활동(Live Activities)을 켜주세요."
            return
        }

        // 이미 떠 있는 Activity 재연결 — 앱 재실행/백그라운드 작업은 새 프로세스라 메모리 참조(activity)가 nil이라
        // 매번 새로 만들어 '중복'이 생겼다. 살아있는 것을 다시 잡고, 2개 이상이면 하나만 남기고 정리한다.
        let running = Activity<ScheduleActivityAttributes>.activities
        if activity == nil { activity = running.first }
        if running.count > 1 {
            let keepID = activity?.id
            Task { for a in running where a.id != keepID { await a.end(nil, dismissalPolicy: .immediate) } }
        }

        // 오늘 일정이 없으면 진행 중인 Activity 종료.
        guard !plan.isEmpty else {
            status = "다가오는 일정이 없어 표시할 게 없어요 — 오늘/곧 있을 일정을 하나 만들어 보세요."
            Task { await end() }
            return
        }

        let state = plan.contentState()
        let content = ActivityContent(state: state, staleDate: plan.dayEnd)

        if let activity {
            Task { await activity.update(content) }
            status = "✅ 실시간 활동 갱신됨 — 잠금화면·다이나믹 아일랜드를 확인하세요."
        } else {
            do {
                let attributes = ScheduleActivityAttributes(dayLabel: dayLabel)
                activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                status = "✅ 실시간 활동 시작됨 — 잠금화면·다이나믹 아일랜드를 확인하세요."
            } catch {
                status = "❌ 시작 실패: \(error.localizedDescription)"
            }
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
