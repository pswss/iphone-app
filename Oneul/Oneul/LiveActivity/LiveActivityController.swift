#if os(iOS)
import ActivityKit
import Foundation
import Observation
import os.log

/// 잠금화면/다이나믹 아일랜드 Live Activity를 시작·갱신·종료.
/// 서버 없이 동작 — 앱이 떠 있을 때 갱신하고, 카운트다운/진행 바는 위젯이 스스로 굴립니다.
@Observable
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private init() {}

    private let log = Logger(subsystem: "com.oneul.app", category: "LiveActivity")

    /// 마지막 시작/갱신 시도 결과 — 진단용(Xcode 콘솔에서도 같은 내용 출력).
    var status = "아직 시도 안 함 — 오늘 탭을 열어 보세요." {
        didSet {
            log.info("\(self.status, privacy: .public)")   // devicectl 콘솔에서도 unified log로 확인
        }
    }

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
        if let a = activity { PushSync.shared.observe(a) }   // update 푸시 토큰 구독(재연결 포함)
        if running.count > 1 {
            let keepID = activity?.id
            log.info("중복 정리: \(running.count)개 중 \(keepID?.prefix(6) ?? "nil", privacy: .public) 유지")
            Task { for a in running where a.id != keepID { await a.end(nil, dismissalPolicy: .immediate) } }
        }

        let state = plan.contentState()
        // staleDate는 최소 '오늘 자정'까지 — 과거(저녁·일정 종료 후)면 즉시 stale로 숨고,
        // 15분처럼 짧으면 저녁에 켠 LA가 금방 흐려지던 문제.
        let endOfToday = Calendar.current.date(
            byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let content = ActivityContent(state: state, staleDate: max(plan.dayEnd, endOfToday))

        if let activity {
            Task { await activity.update(content) }
            status = "✅ 실시간 활동 갱신됨 — 잠금화면·다이나믹 아일랜드를 확인하세요."
        } else {
            let attributes = ScheduleActivityAttributes(dayLabel: dayLabel)
            let stateBytes = (try? JSONEncoder().encode(state))?.count ?? -1   // 4KB 제한 진단용
            do {
                activity = try Activity.request(attributes: attributes, content: content,
                                                pushType: PushConfig.enabled ? .token : nil)   // 서버 갱신 허용
                if let a = activity { PushSync.shared.observe(a); watchState(a) }
                status = "✅ 실시간 활동 시작됨 — 잠금화면·다이나믹 아일랜드를 확인하세요."
            } catch {
                // pushType .token은 푸시 프로비저닝이 어긋나면 실패할 수 있음 → 로컬 전용으로 한 번 더
                if PushConfig.enabled,
                   let a = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
                    activity = a
                    status = "✅ 시작됨(로컬 전용) — 푸시 시작은 실패해 원격 갱신 없이 동작: \((error as NSError).domain) \((error as NSError).code)"
                } else {
                    let ns = error as NSError
                    status = "❌ 시작 실패 [\(ns.domain) \(ns.code) · 상태 \(stateBytes)B]: \(error.localizedDescription)"
                }
            }
        }
        PushSync.shared.sync(plan: plan, dayLabel: dayLabel)   // 경계 시각 스케줄 서버 등록
    }

    /// 시작 후 시스템이 곧바로 끝내는지 관측(진단) — dismissed/ended가 찍히면 시스템 측 종료.
    private var watchedID: String?
    private func watchState(_ a: Activity<ScheduleActivityAttributes>) {
        guard watchedID != a.id else { return }
        watchedID = a.id
        Task {
            for await st in a.activityStateUpdates {
                log.info("상태 변화: \(String(describing: st), privacy: .public) (id \(a.id.prefix(6), privacy: .public))")
            }
        }
    }

    /// 진행 중인 모든 Activity 종료.
    func end() async {
        log.info("end() 호출됨")
        for activity in Activity<ScheduleActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
    }
}
#endif
