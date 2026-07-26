// 반복 시리즈 편집·무기한 보충 하네스 — 실제 EventActions 경로 검증.
// 실행: harness/run_series_edit.sh (swiftc 단독 컴파일, Xcode 테스트 타깃 없음)
// 인메모리 ModelContainer + 실제 EventActions 경로를 그대로 태운다.
import Foundation
import SwiftData

@main
struct SeriesEditHarness {
    enum HarnessError: Error { case forcedReplacementFailure }

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

        // T9 — source 일정 단일 편집: 저장된 편집본은 사용자 소유, 원본 자리는 톰스톤으로 보호.
        do {
            let ctx = try freshContext()
            let (_, first) = try seedTimetable(ctx)
            let original = (source: first.source, title: first.title, start: first.start)
            let movedStart = first.start.addingTimeInterval(1800)
            let saved = EventActions.update(
                first, title: "수학 심화", start: movedStart,
                end: movedStart.addingTimeInterval(5400), location: "2학년 1반", notes: "오답 노트",
                reminderMinutes: 30, reminderMinutes2: 10, pinned: true, in: ctx)
            let edited = try fetchAll(ctx).first { $0.id == first.id }
            check(saved && edited?.title == "수학 심화" && edited?.location == "2학년 1반"
                  && edited?.start == movedStart && edited?.end == movedStart.addingTimeInterval(5400)
                  && edited?.reminderMinutes == 30 && edited?.reminderMinutes2 == 10
                  && edited?.pinned == true && edited?.notes == "오답 노트" && edited?.source == "",
                  "T9a atomic single update persists every editable field and claims source")
            check(SourceTombstones.contains(source: original.source, title: original.title, start: original.start),
                  "T9b successful source update records original-slot tombstone")
        }

        // T10 — 한·영 시험 의미: 시험 자체만 알림, 공부/준비 일정은 제외.
        let schoolExams = ["중간고사", "Math exam", "English test", "Midterm", "Final", "Mock exam", "Reading assessment"]
        check(schoolExams.allSatisfy { ScheduleEvent(title: $0).examKind == .school },
              "T10a Korean and English school-exam terms classify as school")
        let csatExams = ["수능", "CSAT", "College Scholastic Ability Test"]
        check(csatExams.allSatisfy { ScheduleEvent(title: $0).examKind == .csat },
              "T10b Korean and English CSAT terms classify as csat")
        let preparation = ["시험공부", "Exam prep", "Test preparation", "Study for final", "CSAT review"]
        check(preparation.allSatisfy { ScheduleEvent(title: $0).examKind == .none },
              "T10c exam prep, study, and review stay non-exams")
        check(ScheduleEvent(title: "Final project presentation").examKind == .none,
              "T10d non-exam use of final stays non-exam")
        check(ExamKind.school.checklist(english: true) == ["watch", "writing tools"]
              && ExamKind.csat.checklist(english: true) == ["watch", "writing tools", "admission ticket", "photo ID"],
              "T10e English school/CSAT checklists are localized")

        // T11 — 출처 교체는 실패 시 기존 데이터를 보존하고, 성공 시 사용자 일정은 건드리지 않는다.
        do {
            let ctx = try freshContext()
            let start = baseMonday()
            let oldTimetable = ScheduleEvent(title: "수학", start: start, end: start.addingTimeInterval(3600),
                                             reminderMinutes: -1, source: "timetable")
            let oldAcademic = ScheduleEvent(title: "시험", start: start, end: start.addingTimeInterval(3600),
                                            reminderMinutes: -1, source: "academic")
            let oldIDs = Set([oldTimetable.id, oldAcademic.id])
            ctx.insert(oldTimetable)
            ctx.insert(oldAcademic)
            ctx.insert(ScheduleEvent(title: "개인 일정", start: start, end: start.addingTimeInterval(3600),
                                     reminderMinutes: -1))
            try ctx.save()

            do {
                let _: Int = try EventActions.replaceSources(["timetable", "academic"], in: ctx) { replacement in
                    replacement.insert(ScheduleEvent(title: "미완성 새 수업", start: start,
                                                     end: start.addingTimeInterval(3600),
                                                     reminderMinutes: -1, source: "timetable"))
                    throw HarnessError.forcedReplacementFailure
                }
            } catch HarnessError.forcedReplacementFailure {}

            let afterFailure = try fetchAll(ModelContext(ctx.container))
            check(afterFailure.count == 3
                  && afterFailure.contains { $0.id == oldTimetable.id && $0.source == "timetable" }
                  && afterFailure.contains { $0.id == oldAcademic.id && $0.source == "academic" }
                  && afterFailure.contains { $0.title == "개인 일정" && $0.source.isEmpty }
                  && !afterFailure.contains { $0.title == "미완성 새 수업" },
                  "T11a failed source replacement preserves last-known-good data")

            let _: Int = try EventActions.replaceSources(["timetable", "academic"], in: ctx) { replacement in
                replacement.insert(ScheduleEvent(title: "수학", start: start,
                                                 end: start.addingTimeInterval(3600),
                                                 reminderMinutes: -1, source: "timetable"))
                replacement.insert(ScheduleEvent(title: "시험", start: start,
                                                 end: start.addingTimeInterval(3600),
                                                 reminderMinutes: -1, source: "academic"))
                return 2
            }
            let afterSuccess = try fetchAll(ctx)
            check(afterSuccess.count == 3
                  && afterSuccess.contains { $0.title == "수학" && $0.source == "timetable" && !oldIDs.contains($0.id) }
                  && afterSuccess.contains { $0.title == "시험" && $0.source == "academic" && !oldIDs.contains($0.id) }
                  && afterSuccess.contains { $0.title == "개인 일정" && $0.source.isEmpty }
                  && afterSuccess.allSatisfy { !oldIDs.contains($0.id) || $0.source.isEmpty },
                  "T11b successful source replacement swaps generated data and keeps user data")
        }

        // T12 — 삭제 Undo는 원본 필드·시리즈 cursor·source 톰스톤을 함께 복원한다.
        do {
            let ctx = try freshContext()
            let start = baseMonday()
            let generatedThrough = Calendar.current.date(byAdding: .month, value: 6, to: start)!
            let original = ScheduleEvent(
                title: "원본 수학", start: start, end: start.addingTimeInterval(5400),
                location: "2학년 1반", notes: "준비물", reminderMinutes: 30, reminderMinutes2: 10,
                recurrenceRaw: Recurrence.weekly.rawValue, seriesID: "undo-single",
                recurrenceGeneratedThrough: generatedThrough, source: "timetable", pinned: true)
            ctx.insert(original)
            try ctx.save()
            let originalID = original.id

            let receipt = EventActions.deleteSingle(original, in: ctx)
            let afterDelete = try fetchAll(ctx)
            check(receipt?.count == 1 && afterDelete.isEmpty
                  && SourceTombstones.contains(source: "timetable", title: "원본 수학", start: start),
                  "T12a delete receipt commits deletion and source tombstone")
            let undone = receipt.map { EventActions.undoDeletion($0, in: ctx) } ?? false
            let restored = try fetchAll(ctx).first
            check(undone && restored?.id == originalID && restored?.title == "원본 수학"
                  && restored?.location == "2학년 1반" && restored?.notes == "준비물"
                  && restored?.start == start && restored?.end == start.addingTimeInterval(5400)
                  && restored?.reminderMinutes == 30 && restored?.reminderMinutes2 == 10
                  && restored?.recurrenceRaw == Recurrence.weekly.rawValue
                  && restored?.seriesID == "undo-single"
                  && restored?.recurrenceGeneratedThrough == generatedThrough
                  && restored?.source == "timetable" && restored?.pinned == true
                  && !SourceTombstones.contains(source: "timetable", title: "원본 수학", start: start),
                  "T12b undo restores every field, original id, and removes its tombstone")
        }

        do {
            let ctx = try freshContext()
            let start = baseMonday()
            EventActions.create(title: "연속 수업", start: start, end: start.addingTimeInterval(3600), location: "",
                                reminderMinutes: -1, recurrence: .weekly, weekdays: [2],
                                source: "timetable", into: ctx)
            let initial = try fetchAll(ctx)
            let originalIDs = Set(initial.map(\.id))
            let originalCursors = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.recurrenceGeneratedThrough) })
            let cutoff = initial[10]
            let receipt = EventActions.deleteFutureSeries(from: cutoff, in: ctx)
            let closed = try fetchAll(ctx)
            let closedWasClosed = closed.count == 10
                && closed.allSatisfy { $0.recurrenceGeneratedThrough == nil }
            let undone = receipt.map { EventActions.undoDeletion($0, in: ctx) } ?? false
            let restored = try fetchAll(ctx)
            let restoredIDs = Set(restored.map(\.id))
            let cursorMismatches = restored.filter {
                $0.recurrenceGeneratedThrough != (originalCursors[$0.id] ?? nil)
            }.count
            let blocked = restored.filter {
                SourceTombstones.contains(source: $0.source, title: $0.title, start: $0.start)
            }.count
            check(closedWasClosed,
                  "T12c future-series delete closes surviving cursor")
            check(undone && restoredIDs == originalIDs && cursorMismatches == 0 && blocked == 0,
                  "T12d future-series undo restores ids/cursors/tombstones "
                  + "(count \(restored.count)/\(initial.count), ids \(restoredIDs.count)/\(originalIDs.count), "
                  + "cursor mismatches \(cursorMismatches), blocked \(blocked))")
        }

        do {
            let ctx = try freshContext()
            let start = baseMonday()
            EventActions.create(title: "연속 삭제", start: start, end: start.addingTimeInterval(3600), location: "",
                                reminderMinutes: -1, recurrence: .weekly, weekdays: [2],
                                source: "timetable", into: ctx)
            let initial = try fetchAll(ctx)
            let originalIDs = Set(initial.map(\.id))
            let originalCursors = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0.recurrenceGeneratedThrough) })
            if initial.count > 20 {
                let first = EventActions.deleteFutureSeries(from: initial[20], in: ctx)
                let remaining = try fetchAll(ctx)
                let second = EventActions.deleteFutureSeries(from: remaining[10], in: ctx)
                let merged = first.flatMap { firstReceipt in
                    second.map { firstReceipt.merging($0) }
                }
                let undone = merged.map { EventActions.undoDeletion($0, in: ctx) } ?? false
                let restored = try fetchAll(ctx)
                let cursorMismatches = restored.filter {
                    $0.recurrenceGeneratedThrough != (originalCursors[$0.id] ?? nil)
                }.count
                check(undone && Set(restored.map(\.id)) == originalIDs && cursorMismatches == 0,
                      "T12e merged same-series deletes restore every event and original cursor")
            } else {
                check(false, "T12e merged same-series deletes had enough generated occurrences")
            }
        }

        // T13 — AI가 쓰는 혼합 batch는 실패 시 0건, 성공 시 전부를 한 번에 반영한다.
        do {
            let ctx = try freshContext()
            let start = baseMonday()
            let updateTarget = ScheduleEvent(title: "수정 전", start: start,
                                             end: start.addingTimeInterval(3600),
                                             reminderMinutes: -1, source: "timetable")
            let deleteTarget = ScheduleEvent(title: "수정 전", start: start,
                                             end: start.addingTimeInterval(7200),
                                             reminderMinutes: -1, source: "timetable")
            ctx.insert(updateTarget)
            ctx.insert(deleteTarget)
            try ctx.save()

            do {
                let _: Int = try EventActions.performAtomically(in: ctx) { batch, tombstones in
                    let all = try batch.fetch(FetchDescriptor<ScheduleEvent>())
                    let u = all.first { $0.id == updateTarget.id }!
                    let d = all.first { $0.id == deleteTarget.id }!
                    tombstones.append(EventActions.stageUpdate(
                        u, title: "수정 후", start: u.start, end: u.end, location: "",
                        notes: "", reminderMinutes: -1, reminderMinutes2: -1, pinned: false))
                    tombstones.append(EventActions.stageDeleteSingle(d, in: batch))
                    _ = EventActions.stageCreate(title: "새 일정", start: start.addingTimeInterval(14400),
                                                 end: start.addingTimeInterval(18000), location: "",
                                                 reminderMinutes: -1, recurrence: .none, into: batch)
                    throw HarnessError.forcedReplacementFailure
                }
            } catch HarnessError.forcedReplacementFailure {}

            let failed = try fetchAll(ModelContext(ctx.container))
            check(failed.count == 2 && failed.contains { $0.id == updateTarget.id && $0.title == "수정 전" }
                  && failed.contains { $0.id == deleteTarget.id }
                  && !failed.contains { $0.title == "새 일정" }
                  && !SourceTombstones.contains(source: "timetable", title: "수정 전", start: start),
                  "T13a failed mixed batch leaves data and tombstones untouched")

            let receipt: EventActions.DeletionReceipt = try EventActions.performAtomically(in: ctx) { batch, tombstones in
                let all = try batch.fetch(FetchDescriptor<ScheduleEvent>())
                let u = all.first { $0.id == updateTarget.id }!
                let d = all.first { $0.id == deleteTarget.id }!
                let updateTombstone = EventActions.stageUpdate(
                    u, title: "수정 후", start: u.start, end: u.end, location: "",
                    notes: "", reminderMinutes: -1, reminderMinutes2: -1, pinned: false)
                tombstones.append(updateTombstone)
                let staged = EventActions.stageDeleteSingleWithReceipt(d, in: batch)
                tombstones += staged.tombstones
                _ = EventActions.stageCreate(title: "새 일정", start: start.addingTimeInterval(14400),
                                             end: start.addingTimeInterval(18000), location: "",
                                             reminderMinutes: -1, recurrence: .none, into: batch)
                let owned = staged.tombstones.filter { candidate in
                    !SourceTombstones.contains(
                        source: candidate.source, title: candidate.title, start: candidate.start)
                        && !(updateTombstone.source == candidate.source
                             && updateTombstone.title == candidate.title
                             && updateTombstone.start == candidate.start)
                }
                return staged.receipt.withTombstones(owned)
            }
            let succeeded = try fetchAll(ctx)
            check(succeeded.count == 2
                  && succeeded.contains { $0.id == updateTarget.id && $0.title == "수정 후" && $0.source.isEmpty }
                  && !succeeded.contains { $0.id == deleteTarget.id }
                  && succeeded.contains { $0.title == "새 일정" }
                  && SourceTombstones.contains(source: "timetable", title: "수정 전", start: start),
                  "T13b successful mixed batch commits every change and deferred tombstones")

            let undone = EventActions.undoDeletion(receipt, in: ctx)
            let afterUndo = try fetchAll(ctx)
            check(undone && afterUndo.count == 3
                  && afterUndo.contains { $0.id == updateTarget.id && $0.title == "수정 후" }
                  && afterUndo.contains { $0.id == deleteTarget.id && $0.title == "수정 전" }
                  && afterUndo.contains { $0.title == "새 일정" }
                  && SourceTombstones.contains(source: "timetable", title: "수정 전", start: start),
                  "T13c deletion-only undo preserves an update-owned tombstone")
        }

        print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
