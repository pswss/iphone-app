// 반복 시리즈 편집·무기한 보충 하네스 — 실제 EventActions 경로 검증.
// 실행: harness/run_series_edit.sh (swiftc 단독 컴파일, Xcode 테스트 타깃 없음)
// 인메모리 ModelContainer + 실제 EventActions 경로를 그대로 태운다.
import Foundation
import SwiftData

@main
struct SeriesEditHarness {
    static var failures = 0

    static func check(_ cond: Bool, _ name: String) {
        print("\(cond ? "PASS" : "FAIL"): \(name)")
        if !cond { failures += 1 }
    }

    static var liveContainers: [ModelContainer] = []   // 컨테이너가 컨텍스트보다 먼저 해제되면 fetch가 빈 배열

    /// 테스트마다 새 인메모리 컨테이너 + 톰스톤 초기화.
    static func freshContext() throws -> ModelContext {
        UserDefaults.standard.removeObject(forKey: "sourceTombstones")
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ScheduleEvent.self, configurations: config)
        liveContainers.append(container)
        return ModelContext(container)
    }

    /// 다음 주 월요일 09:00 (톰스톤 60일 정리 창 안에 있도록 항상 미래 기준).
    static func baseMonday() -> Date {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date().addingTimeInterval(7 * 86400))
        while cal.component(.weekday, from: day) != 2 {
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
    }

    /// 월·수 매주 2주치 시간표 임포트(NEIS 재가져오기 시뮬레이션에도 사용 — 톰스톤에 막히면 0건).
    static func importTimetable(_ context: ModelContext, title: String = "수학") {
        let start = baseMonday()
        let horizon = Calendar.current.date(byAdding: .day, value: 13, to: start)!
        EventActions.create(title: title, start: start, end: start.addingTimeInterval(3600), location: "",
                            reminderMinutes: -1, recurrence: .weekly,
                            weekdays: [2, 4], endDate: horizon, source: "timetable", into: context)
    }

    /// 임포트 + (전체 이벤트, 첫 회차) 반환. 초기 시드 전용(0건이면 throw).
    static func seedTimetable(_ context: ModelContext, title: String = "수학") throws -> (all: [ScheduleEvent], first: ScheduleEvent) {
        importTimetable(context, title: title)
        let all = try fetchAll(context)
        guard let first = all.first else { throw NSError(domain: "seed", code: 1) }
        return (all, first)
    }

    static func fetchAll(_ context: ModelContext) throws -> [ScheduleEvent] {
        try context.fetch(FetchDescriptor<ScheduleEvent>()).sorted { $0.start < $1.start }
    }

    static func main() throws {
        setvbuf(stdout, nil, _IONBF, 0)   // fatalError 시에도 진행 로그 유실 방지
        // T0 — 순수 필터: 사용자 소유("")는 절대 안 막힘, 시간표는 키 일치 시 막힘
        let key = "timetable|수학|1000"
        check(!SourceTombstones.isBlocked(source: "", title: "수학",
                                          start: Date(timeIntervalSince1970: 1000), in: [key]),
              "T0a isBlocked: user-owned(source \"\") never blocked")
        check(SourceTombstones.isBlocked(source: "timetable", title: "수학",
                                         start: Date(timeIntervalSince1970: 1000), in: [key]),
              "T0b isBlocked: matching timetable key blocked")

        // T1 — 시리즈 전체 편집(제목·시각 그대로): 회차 수 유지돼야 함(톰스톤 자기충돌로 증발 금지)
        do {
            let ctx = try freshContext()
            let (all, first) = try seedTimetable(ctx)
            let n = all.count
            EventActions.editFutureSeries(from: first, title: "수학", start: first.start,
                                          end: first.end, location: "", reminderMinutes: -1,
                                          recurrence: .weekly, weekdays: [2, 4],
                                          endDate: all.last!.start, in: ctx)
            let after = try fetchAll(ctx)
            check(after.count == n, "T1 edit same title/time keeps \(n) occurrences (got \(after.count))")
        }

        // T2 — 제목 바꿔 편집: 재생성분은 사용자 소유(source "")여야 NEIS 갱신이 안 되돌림
        do {
            let ctx = try freshContext()
            let (all, first) = try seedTimetable(ctx)
            let n = all.count
            EventActions.editFutureSeries(from: first, title: "수학심화", start: first.start,
                                          end: first.end, location: "", reminderMinutes: -1,
                                          recurrence: .weekly, weekdays: [2, 4],
                                          endDate: all.last!.start, in: ctx)
            let after = try fetchAll(ctx)
            check(after.count == n && after.allSatisfy { $0.title == "수학심화" && $0.source.isEmpty },
                  "T2 edited series is user-owned source \"\" (got \(after.count) events, sources \(Set(after.map(\.source))))")
        }

        // T3 — 진짜 이후 전체 삭제: 지워지고, NEIS 재가져오기가 같은 자리 재생성 못 함
        do {
            let ctx = try freshContext()
            let (_, first) = try seedTimetable(ctx)
            EventActions.deleteFutureSeries(from: first, in: ctx)
            let deleted = try fetchAll(ctx)
            check(deleted.isEmpty, "T3a delete-future removes all (got \(deleted.count))")
            importTimetable(ctx)   // NEIS 재가져오기 시뮬레이션(같은 제목·시각·source)
            let after = try fetchAll(ctx)
            check(after.isEmpty, "T3b tombstones block NEIS re-import of deleted slots (got \(after.count))")
        }

        // T4 — 사용자 편집 후 NEIS 갱신(deleteBySource + 재가져오기): 편집본 생존, 원본 미부활
        do {
            let ctx = try freshContext()
            let (all, first) = try seedTimetable(ctx)
            let n = all.count
            EventActions.editFutureSeries(from: first, title: "수학", start: first.start,
                                          end: first.end, location: "", reminderMinutes: -1,
                                          recurrence: .weekly, weekdays: [2, 4],
                                          endDate: all.last!.start, in: ctx)
            EventActions.deleteBySource("timetable", in: ctx)   // NEIS 갱신 1단계
            importTimetable(ctx)                                 // 2단계: 원본 재가져오기
            let after = try fetchAll(ctx)
            let userOwned = after.filter { $0.source.isEmpty }
            let reimported = after.filter { $0.source == "timetable" }
            check(userOwned.count == n && reimported.isEmpty,
                  "T4 NEIS refresh keeps \(n) user-edited, revives 0 originals (got user \(userOwned.count), timetable \(reimported.count))")
        }

        // T5 — 종료일 없는 주간 반복: 6개월 미만 남으면 1년 창을 보충하고, 재실행해도 중복 없음
        do {
            let ctx = try freshContext()
            let start = baseMonday()
            EventActions.create(title: "운동", start: start, end: start.addingTimeInterval(3600), location: "",
                                reminderMinutes: -1, recurrence: .weekly, weekdays: [2, 4], into: ctx)
            let initial = try fetchAll(ctx)
            let oldLast = initial.last!.start
            let advanced = Calendar.current.date(byAdding: .month, value: 8, to: start)!
            let added = EventActions.replenishOpenEndedWeeklySeries(now: advanced, in: ctx)
            let once = try fetchAll(ctx)
            let addedAgain = EventActions.replenishOpenEndedWeeklySeries(now: advanced, in: ctx)
            let twice = try fetchAll(ctx)
            let uniqueStarts = Set(twice.map { Int($0.start.timeIntervalSince1970) })
            check(added > 0 && once.last!.start > oldLast,
                  "T5a open weekly series extends past initial one-year batch (added \(added))")
            check(addedAgain == 0 && twice.count == once.count && uniqueStarts.count == twice.count,
                  "T5b replenishment is idempotent with no duplicate starts (got \(twice.count))")
        }

        // T6 — 명시적 종료일 시리즈: 오래 지나도 자동 연장하지 않음
        do {
            let ctx = try freshContext()
            let start = baseMonday()
            let endDate = Calendar.current.date(byAdding: .day, value: 13, to: start)!
            EventActions.create(title: "단기 수업", start: start, end: start.addingTimeInterval(3600), location: "",
                                reminderMinutes: -1, recurrence: .weekly, weekdays: [2, 4], endDate: endDate, into: ctx)
            let initial = try fetchAll(ctx)
            let advanced = Calendar.current.date(byAdding: .year, value: 2, to: start)!
            let added = EventActions.replenishOpenEndedWeeklySeries(now: advanced, in: ctx)
            let after = try fetchAll(ctx)
            check(added == 0 && after.count == initial.count && after.allSatisfy { $0.recurrenceGeneratedThrough == nil },
                  "T6 explicit-ended weekly series stays closed (got \(after.count))")
        }

        // T7 — 마지막 materialized 회차만 삭제: cursor가 삭제 날짜를 되살리지 않고 그 이후부터 보충
        do {
            let ctx = try freshContext()
            let start = baseMonday()
            EventActions.create(title: "독서", start: start, end: start.addingTimeInterval(3600), location: "",
                                reminderMinutes: -1, recurrence: .weekly, weekdays: [2], into: ctx)
            let initial = try fetchAll(ctx)
            let deletedStart = initial.last!.start
            EventActions.deleteSingle(initial.last!, in: ctx)
            let advanced = Calendar.current.date(byAdding: .month, value: 8, to: start)!
            let added = EventActions.replenishOpenEndedWeeklySeries(now: advanced, in: ctx)
            let after = try fetchAll(ctx)
            check(added > 0 && !after.contains { $0.start == deletedStart },
                  "T7 single-deleted final occurrence stays deleted while later dates replenish")
        }

        // T8 — 이후 전체 삭제: 남은 과거 회차가 open marker를 잃어 다시 자라지 않음
        do {
            let ctx = try freshContext()
            let start = baseMonday()
            EventActions.create(title: "스터디", start: start, end: start.addingTimeInterval(3600), location: "",
                                reminderMinutes: -1, recurrence: .weekly, weekdays: [2], into: ctx)
            let initial = try fetchAll(ctx)
            let cutoff = initial[10]
            EventActions.deleteFutureSeries(from: cutoff, in: ctx)
            let closed = try fetchAll(ctx)
            let advanced = Calendar.current.date(byAdding: .year, value: 2, to: start)!
            let added = EventActions.replenishOpenEndedWeeklySeries(now: advanced, in: ctx)
            let after = try fetchAll(ctx)
            check(closed.count == 10 && added == 0 && after.count == closed.count
                  && after.allSatisfy { $0.recurrenceGeneratedThrough == nil },
                  "T8 delete-future closes surviving history (got \(after.count))")
        }

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
