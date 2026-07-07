#if os(iOS)
import Foundation
import ActivityKit

/// Live Activity 푸시 동기화 — 오늘 일정의 "경계 시각별 콘텐츠 상태"를 서버(Cloudflare Worker)에 등록.
/// 서버 cron이 각 시각에 APNs로 쏘면:
/// - push-to-start: 앱이 꺼져 있어도 첫 일정 전에 Live Activity 자동 시작
/// - update: 일정 시작/끝마다 앱 없이 정확히 상태 전환 (초 단위 카운트다운은 여전히 로컬 타이머)
@MainActor
final class PushSync {
    static let shared = PushSync()
    private init() {}

    private var startToken: String?
    private var updateToken: String?
    private var lastPlan: DayPlan?
    private var lastLabel = ""
    private var uploadTask: Task<Void, Never>?
    private var observingActivityID: String?

    private var deviceID: String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "pushDeviceID") { return id }
        let id = UUID().uuidString
        d.set(id, forKey: "pushDeviceID")
        return id
    }

    /// 앱 시작 시 1회 — push-to-start 토큰 구독(iOS가 언제든 새 토큰을 줄 수 있음).
    func begin() {
        guard PushConfig.enabled else { return }
        Task {
            for await data in Activity<ScheduleActivityAttributes>.pushToStartTokenUpdates {
                await MainActor.run {
                    self.startToken = Self.hex(data)
                    self.scheduleUpload()
                }
            }
        }
    }

    /// 진행 중 Activity의 update 토큰 구독(컨트롤러가 시작/재연결 시 호출).
    func observe(_ activity: Activity<ScheduleActivityAttributes>) {
        guard PushConfig.enabled, observingActivityID != activity.id else { return }
        observingActivityID = activity.id
        Task {
            for await data in activity.pushTokenUpdates {
                await MainActor.run {
                    self.updateToken = Self.hex(data)
                    self.scheduleUpload()
                }
            }
        }
    }

    /// 최신 플랜 반영(컨트롤러 refresh마다) → 디바운스 업로드.
    func sync(plan: DayPlan, dayLabel: String) {
        guard PushConfig.enabled else { return }
        lastPlan = plan
        lastLabel = dayLabel
        scheduleUpload()
    }

    private func scheduleUpload() {
        uploadTask?.cancel()
        uploadTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)   // 연속 갱신 묶기
            guard !Task.isCancelled else { return }
            await upload()
        }
    }

    private func upload() async {
        guard PushConfig.enabled, let url = PushConfig.serverURL,
              let plan = lastPlan, !plan.isEmpty,
              startToken != nil || updateToken != nil else { return }

        let now = Date()
        let enc = JSONEncoder()   // 기본 전략 — ActivityKit의 content-state 디코딩과 일치

        // 경계 시각: 각 일정의 시작·끝(미래, 하루 범위 내) + 2초 여유
        var times = Set<Date>()
        for e in plan.events {
            for t in [e.start, e.end] where t > now && t <= plan.dayEnd { times.insert(t) }
        }

        var items: [[String: Any]] = []

        // '지금' 상태를 항목으로 — 첫 경계가 오기 전에도 서버가 이걸 기준으로
        // 분단위 재전송을 해서 잠금화면 남은 시간이 스스로 갱신된다(내용은 동일, 재렌더만).
        if updateToken != nil {
            let state = plan.contentState(at: now)
            if let data = try? enc.encode(state),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                items.append(["at": Int(now.timeIntervalSince1970), "event": "update", "state": obj])
            }
        }

        for t in times.sorted() {
            let state = plan.contentState(at: t.addingTimeInterval(2))
            guard let data = try? enc.encode(state),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            items.append(["at": Int(t.timeIntervalSince1970) + 2, "event": "update", "state": obj])
        }

        // push-to-start: 첫 일정 30분 전(미래일 때만) — 앱이 꺼져 있어도 아침에 자동 시작
        if startToken != nil,
           let first = plan.events.map(\.start).min(), first > now.addingTimeInterval(120) {
            let at = max(now.addingTimeInterval(60), first.addingTimeInterval(-30 * 60))
            let state = plan.contentState(at: at.addingTimeInterval(2))
            if let data = try? enc.encode(state),
               let obj = try? JSONSerialization.jsonObject(with: data) {
                items.append(["at": Int(at.timeIntervalSince1970), "event": "start",
                              "state": obj, "attributes": ["dayLabel": lastLabel]])
            }
        }
        guard !items.isEmpty else { return }

        #if DEBUG
        let sandbox = true    // Xcode 실행 = development aps → 샌드박스 APNs
        #else
        let sandbox = false
        #endif

        let body: [String: Any] = [
            "deviceID": deviceID,
            "updateToken": updateToken as Any,
            "startToken": startToken as Any,
            "sandbox": sandbox,
            "staleAt": Int(plan.dayEnd.timeIntervalSince1970),
            "items": items,
        ]
        var req = URLRequest(url: url.appendingPathComponent("register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(PushConfig.registerKey, forHTTPHeaderField: "X-Oneul-Key")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
#endif
