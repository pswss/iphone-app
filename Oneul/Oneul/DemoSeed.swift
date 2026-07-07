#if DEBUG
import Foundation
import SwiftData

/// 앱스토어 스크린샷용 데모 일정 시드 — `-demoSeed` 런치 아규먼트로만 동작(DEBUG 전용).
/// 알림은 전부 끔(reminder -1) — 헤드리스 시뮬레이터에서 권한 알럿이 뜨면 안 됨.
enum DemoSeed {
    @MainActor
    static func runIfRequested(container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("-demoSeed") else { return }
        let ctx = container.mainContext
        let marker = "demo-seed"
        // 중복 방지 — 이미 시드했으면 통과
        let existing = (try? ctx.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
        guard !existing.contains(where: { $0.notes == marker }) else { return }

        // '지금'을 정시로 내림한 기준 시각에서 상대 배치 — 몇 시에 찍어도
        // 진행 중 1개 + 지나간 2개(흐림) + 예정 여러 개가 현재선 주변에 보인다.
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day, .hour], from: Date())
        c.minute = 0
        let base = cal.date(from: c)!
        func rel(_ h: Double, len: Double) -> (Date, Date) {
            let s = base.addingTimeInterval(h * 3600)
            return (s, s.addingTimeInterval(len * 3600))
        }

        let day: [(String, Double, Double)] = [   // (제목, 기준 대비 시작(시간), 길이(시간)) — 시간대 중립 제목
            ("러닝", -3.0, 0.7),
            ("팀 프로젝트 회의", -2.0, 1.5),
            ("지우랑 카페", 1.0, 1.0),
            ("과제 집중", 2.5, 1.5),
            ("수영", 4.5, 1.2),
            ("스터디 카페", 6.0, 1.5),
        ]
        for (title, h, len) in day {
            let (s, e) = rel(h, len: len)
            ctx.insert(ScheduleEvent(title: title, start: s, end: e,
                                     notes: marker, reminderMinutes: -1))
        }
        // 진행 중 일정은 실제 now 기준 — 촬영이 몇 분 늦어도 '현재'로 남게
        ctx.insert(ScheduleEvent(title: "영어 회화", start: Date().addingTimeInterval(-20 * 60),
                                 end: Date().addingTimeInterval(55 * 60),
                                 notes: marker, reminderMinutes: -1))
        // 주요 일정(D-day 밴드) — 일주일 뒤 발표
        if let dday = cal.date(byAdding: .day, value: 7, to: base) {
            ctx.insert(ScheduleEvent(title: "포트폴리오 발표", start: dday,
                                     end: dday.addingTimeInterval(3600),
                                     notes: marker, reminderMinutes: -1, pinned: true))
        }
        try? ctx.save()
    }
}
#endif
