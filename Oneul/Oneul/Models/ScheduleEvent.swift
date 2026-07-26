import Foundation
import SwiftData

/// 일정 한 건. SwiftData + CloudKit 동기화 대상.
/// 반복 일정은 같은 `seriesID`를 가진 여러 인스턴스로 materialize 된다.
@Model
final class ScheduleEvent {
    var id: UUID = UUID()
    var title: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var location: String = ""
    var notes: String = ""
    /// 시작 몇 분 전 알림. -1이면 없음.
    var reminderMinutes: Int = 10
    /// 2차 알림(분 전). -1이면 없음. 1차가 설정됐을 때만 노출.
    var reminderMinutes2: Int = -1
    /// Recurrence.rawValue ("none"/"daily"/…).
    var recurrenceRaw: String = "none"
    /// 반복 시리즈 식별자. 빈 값이면 단일 일정.
    var seriesID: String = ""
    /// 종료일 없는 반복에서 이미 생성 범위를 확인한 마지막 날짜. nil이면 명시적 종료/기존 시리즈.
    var recurrenceGeneratedThrough: Date? = nil
    /// 출처 태그. ""=사용자, "timetable"=학교 시간표, "academic"=학사일정. 재가져오기 시 삭제 기준.
    var source: String = ""
    /// 사용자가 '주요 일정'으로 지정 → 상단 스와이프 밴드에 D-day로 표시.
    var pinned: Bool = false

    init(
        id: UUID = UUID(),
        title: String = "",
        start: Date = .now,
        end: Date = .now,
        location: String = "",
        notes: String = "",
        reminderMinutes: Int = 10,
        reminderMinutes2: Int = -1,
        recurrenceRaw: String = "none",
        seriesID: String = "",
        recurrenceGeneratedThrough: Date? = nil,
        source: String = "",
        pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.reminderMinutes2 = reminderMinutes2
        self.recurrenceRaw = recurrenceRaw
        self.seriesID = seriesID
        self.recurrenceGeneratedThrough = recurrenceGeneratedThrough
        self.source = source
        self.pinned = pinned
    }
}

/// 시험 유형 (제목 키워드로 판별). 시험 1일 전 알림·준비물에 사용.
enum ExamKind {
    case none    // 시험 아님
    case school  // 내신 지필 + 모의고사 + 학력평가 — 시계·필기구만
    case csat    // 수능 — 수험표·신분증까지

    /// 기존 한국어 caller용 준비물 체크리스트.
    var checklist: [String] { checklist(english: false) }

    /// 표시 언어에 맞춘 준비물 체크리스트.
    func checklist(english: Bool) -> [String] {
        switch self {
        case .none: return []
        case .school: return english ? ["watch", "writing tools"] : ["시계", "필기구"]
        case .csat:
            return english
                ? ["watch", "writing tools", "admission ticket", "photo ID"]
                : ["시계", "필기구", "수험표", "신분증"]
        }
    }
    var isExam: Bool { self != .none }
}

extension ScheduleEvent {
    /// 해당 날짜에 일정이 걸쳐 있으면 true (멀티데이 일정은 모든 날에 표시).
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return calendar.isDate(start, inSameDayAs: day)
        }
        return start < dayEnd && end > dayStart
    }
    var isRecurring: Bool { !seriesID.isEmpty }

    /// 멀티데이(이틀 이상 걸침) 여부.
    func isMultiDay(calendar: Calendar = .current) -> Bool {
        !calendar.isDate(start, inSameDayAs: end)
    }

    /// 하루짜리 '날 전체' 성격(생일·기념일·23시간 이상) — 그리드 블록 대신 종일 배너로 표시.
    func isDayMarker(calendar: Calendar = .current) -> Bool {
        guard !isMultiDay(calendar: calendar) else { return false }
        if end.timeIntervalSince(start) >= 23 * 3600 { return true }
        return ["생일", "기념일", "birthday", "anniversary"]
            .contains { title.localizedCaseInsensitiveContains($0) }
    }

    /// 종일 배너 아이콘 — 생일은 케이크, 기념일은 하트.
    var bannerIcon: String {
        if title.localizedCaseInsensitiveContains("생일")
            || title.localizedCaseInsensitiveContains("birthday") { return "birthday.cake" }
        if title.localizedCaseInsensitiveContains("기념일")
            || title.localizedCaseInsensitiveContains("anniversary") { return "heart.fill" }
        return "rectangle.expand.vertical"
    }

    /// 제목 키워드로 시험 유형 판별. (수능만 csat, 나머지 시험·모의·평가는 school)
    var examKind: ExamKind {
        let t = title
        let lower = t.lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
        let hasEnglishExam = ["exam", "test", "midterm", "midterms", "finals", "assessment", "csat"]
            .contains { words.contains($0) }
            || (words.contains("final") && (words.count == 1 || words.contains("exam") || words.contains("test")))
        // '시험공부'·'시험 준비'처럼 시험을 준비하는 일정은 시험 자체가 아님 → 전날 준비물 알림 오탐 방지
        let studyWords = ["공부", "준비", "대비", "복습", "특강", "학습"]
        let englishStudyWords = ["prep", "preparation", "study", "review"]
        if studyWords.contains(where: t.contains)
            || (hasEnglishExam && englishStudyWords.contains { words.contains($0) }) {
            return .none
        }
        let isMock = t.contains("모의") || t.contains("학력평가") || t.contains("연합")
        if !isMock && (t.contains("수학능력시험") || t.contains("수능")
                       || words.contains("csat")
                       || lower.contains("college scholastic ability test")) { return .csat }
        let school = ["모의", "학력평가", "연합", "지필", "중간고사", "기말고사", "고사", "시험", "평가"]
        if school.contains(where: t.contains) || hasEnglishExam { return .school }
        return .none
    }
}

// MARK: - 반복 규칙

enum Recurrence: String, CaseIterable, Identifiable {
    case none, daily, weekly, biweekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "없음"
        case .daily: return "매일"
        case .weekly: return "매주"
        case .biweekly: return "2주마다"
        case .monthly: return "매달"
        case .yearly: return "매년"
        }
    }

    /// 다음 발생까지의 간격.
    var step: (component: Calendar.Component, value: Int)? {
        switch self {
        case .none: return nil
        case .daily: return (.day, 1)
        case .weekly: return (.weekOfYear, 1)
        case .biweekly: return (.weekOfYear, 2)
        case .monthly: return (.month, 1)
        case .yearly: return (.year, 1)
        }
    }
}

// MARK: - 자동 갱신 원복 방지 톰스톤
// 사용자가 시간표/학사일정(source != "") 일정을 삭제·수정하면 그 인스턴스 키를 기록해,
// 일일 자동 재가져오기가 같은 자리에 다시 만들어 조용히 원복하는 것을 막는다.
enum SourceTombstones {
    private static let key = "sourceTombstones"

    private static func instanceKey(source: String, title: String, start: Date) -> String {
        "\(source)|\(title)|\(Int(start.timeIntervalSince1970))"
    }

    /// 순수 판정: 이 (source·제목·시작) 인스턴스 생성이 톰스톤 키 집합에 막히는가.
    /// 사용자 소유(source == "")는 절대 막히지 않는다. 하네스 테스트 대상.
    static func isBlocked(source: String, title: String, start: Date, in keys: Set<String>) -> Bool {
        guard !source.isEmpty else { return false }
        return keys.contains(instanceKey(source: source, title: title, start: start))
    }

    static func record(source: String, title: String, start: Date) {
        guard !source.isEmpty else { return }
        var all = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        all.insert(instanceKey(source: source, title: title, start: start))
        // 60일 지난 과거 키는 정리(재가져오기 범위 밖)
        let cutoff = Int(Date().addingTimeInterval(-60 * 86400).timeIntervalSince1970)
        all = Set(all.filter { Int($0.split(separator: "|").last.map(String.init) ?? "") ?? 0 >= cutoff })
        UserDefaults.standard.set(Array(all), forKey: key)
    }

    static func contains(source: String, title: String, start: Date) -> Bool {
        isBlocked(source: source, title: title, start: start,
                  in: Set(UserDefaults.standard.stringArray(forKey: key) ?? []))
    }
}

enum EventActions {
    private struct EditableSnapshot {
        let title: String
        let location: String
        let start: Date
        let end: Date
        let reminderMinutes: Int
        let reminderMinutes2: Int
        let pinned: Bool
        let notes: String
        let source: String

        init(_ event: ScheduleEvent) {
            title = event.title
            location = event.location
            start = event.start
            end = event.end
            reminderMinutes = event.reminderMinutes
            reminderMinutes2 = event.reminderMinutes2
            pinned = event.pinned
            notes = event.notes
            source = event.source
        }

        func restore(_ event: ScheduleEvent) {
            event.title = title
            event.location = location
            event.start = start
            event.end = end
            event.reminderMinutes = reminderMinutes
            event.reminderMinutes2 = reminderMinutes2
            event.pinned = pinned
            event.notes = notes
            event.source = source
        }
    }

    private struct WeeklyTemplate: Hashable {
        let title: String
        let location: String
        let notes: String
        let reminderMinutes: Int
        let reminderMinutes2: Int
        let pinned: Bool
        let source: String
        let hour: Int
        let minute: Int
        let durationSeconds: Int
    }

    /// 일정 생성.
    /// - 반복이 매주이고 `weekdays`(1=일…7=토)가 있으면 그 요일마다 생성.
    /// - `endDate`가 있으면 그날까지. 종료일 없는 주간 반복은 우선 1년치를 만들고 자동 보충한다.
    @discardableResult
    static func create(
        title: String, start: Date, end: Date, location: String, notes: String = "",
        reminderMinutes: Int, reminderMinutes2: Int = -1, recurrence: Recurrence,
        weekdays: Set<Int> = [], endDate: Date? = nil, source: String = "",
        excludeDays: Set<Date> = [], pinned: Bool = false, into context: ModelContext
    ) -> Bool {
        let inserted = stageCreate(
            title: title, start: start, end: end, location: location, notes: notes,
            reminderMinutes: reminderMinutes, reminderMinutes2: reminderMinutes2,
            recurrence: recurrence, weekdays: weekdays, endDate: endDate, source: source,
            excludeDays: excludeDays, pinned: pinned, into: context)
        guard !inserted.isEmpty else { return false }
        do {
            try context.save()
            return true
        } catch {
            for event in inserted { context.delete(event) }
            return false
        }
    }

    static func stageCreate(
        title: String, start: Date, end: Date, location: String, notes: String = "",
        reminderMinutes: Int, reminderMinutes2: Int = -1, recurrence: Recurrence,
        weekdays: Set<Int> = [], endDate: Date? = nil, source: String = "",
        excludeDays: Set<Date> = [], pinned: Bool = false, into context: ModelContext
    ) -> [ScheduleEvent] {
        let duration = max(0, end.timeIntervalSince(start))
        var inserted: [ScheduleEvent] = []

        guard recurrence != .none else {
            if !SourceTombstones.contains(source: source, title: title, start: start) {
                let event = ScheduleEvent(title: title, start: start, end: end,
                                          location: location, notes: notes, reminderMinutes: reminderMinutes,
                                          reminderMinutes2: reminderMinutes2, source: source, pinned: pinned)
                context.insert(event)
                inserted.append(event)
            }
            return inserted
        }

        let cal = Calendar.current
        let seriesID = UUID().uuidString
        let horizon = endDate ?? cal.date(byAdding: .year, value: 1, to: start) ?? start
        let weeklyDays = recurrence == .weekly
            ? (weekdays.isEmpty ? Set([cal.component(.weekday, from: start)]) : weekdays)
            : []
        let generatedThrough = recurrence == .weekly && endDate == nil ? cal.startOfDay(for: horizon) : nil
        let cap = 800
        var count = 0

        if recurrence == .weekly && !weeklyDays.isEmpty {
            // 선택한 요일마다 매주, 종료일까지
            let h = cal.component(.hour, from: start)
            let m = cal.component(.minute, from: start)
            var day = cal.startOfDay(for: start)
            let endDay = cal.startOfDay(for: horizon)
            while day <= endDay && count < cap {
                if weeklyDays.contains(cal.component(.weekday, from: day)), !excludeDays.contains(day),
                   let s = cal.date(bySettingHour: h, minute: m, second: 0, of: day), s >= start,
                   !SourceTombstones.contains(source: source, title: title, start: s) {
                    let event = ScheduleEvent(
                        title: title, start: s, end: s.addingTimeInterval(duration),
                        location: location, notes: notes, reminderMinutes: reminderMinutes,
                        reminderMinutes2: reminderMinutes2,
                        recurrenceRaw: recurrence.rawValue, seriesID: seriesID,
                        recurrenceGeneratedThrough: generatedThrough, source: source, pinned: pinned)
                    context.insert(event)
                    inserted.append(event)
                    count += 1
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        } else if let step = recurrence.step {
            var date = start
            while date <= horizon && count < cap {
                if SourceTombstones.contains(source: source, title: title, start: date) {
                    guard let next = cal.date(byAdding: step.component, value: step.value, to: date) else { break }
                    date = next; continue
                }
                let event = ScheduleEvent(
                    title: title, start: date, end: date.addingTimeInterval(duration),
                    location: location, notes: notes, reminderMinutes: reminderMinutes,
                    reminderMinutes2: reminderMinutes2,
                    recurrenceRaw: recurrence.rawValue, seriesID: seriesID, source: source, pinned: pinned)
                context.insert(event)
                inserted.append(event)
                count += 1
                guard let next = cal.date(byAdding: step.component, value: step.value, to: date) else { break }
                date = next
            }
        }
        return inserted
    }

    /// 종료일 없는 주간 반복의 미래 회차가 6개월 미만 남으면 다시 1년치까지 보충한다.
    @discardableResult
    static func replenishOpenEndedWeeklySeries(
        now: Date = .now, calendar cal: Calendar = .current, in context: ModelContext
    ) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<ScheduleEvent>()) else { return 0 }
        let groups = Dictionary(grouping: all.filter {
            $0.recurrenceGeneratedThrough != nil && $0.recurrenceRaw == Recurrence.weekly.rawValue && !$0.seriesID.isEmpty
        }, by: \ScheduleEvent.seriesID)
        let today = cal.startOfDay(for: now)
        guard let refillThreshold = cal.date(byAdding: .month, value: 6, to: today),
              let target = cal.date(byAdding: .year, value: 1, to: today) else { return 0 }

        var insertedCount = 0
        var changed = false
        for (seriesID, series) in groups {
            guard !series.isEmpty else { continue }

            let generatedThrough = max(
                series.compactMap(\.recurrenceGeneratedThrough).max() ?? .distantPast,
                cal.startOfDay(for: series.map(\.start).max() ?? .distantPast)
            )
            guard generatedThrough < refillThreshold else { continue }

            let weekdays = weeklyWeekdays(from: series, calendar: cal)
            guard !weekdays.isEmpty, let template = weeklyTemplate(from: series, calendar: cal) else { continue }

            var day = max(
                cal.date(byAdding: .day, value: 1, to: generatedThrough) ?? target,
                today
            )
            var additions = 0
            while day <= target && additions < 800 {
                if weekdays.contains(cal.component(.weekday, from: day)),
                   let start = cal.date(bySettingHour: template.hour, minute: template.minute, second: 0, of: day) {
                    context.insert(ScheduleEvent(
                        title: template.title, start: start,
                        end: start.addingTimeInterval(TimeInterval(template.durationSeconds)),
                        location: template.location, notes: template.notes,
                        reminderMinutes: template.reminderMinutes, reminderMinutes2: template.reminderMinutes2,
                        recurrenceRaw: Recurrence.weekly.rawValue, seriesID: seriesID,
                        recurrenceGeneratedThrough: target, source: template.source, pinned: template.pinned))
                    additions += 1
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            for event in series {
                event.recurrenceGeneratedThrough = target
            }
            insertedCount += additions
            changed = true
        }
        if changed { try? context.save() }
        return insertedCount
    }

    /// 1년치 회차에서 반복 요일을 복원. 한두 번 옮긴 단일 회차는 낮은 빈도라 규칙에 섞이지 않는다.
    private static func weeklyWeekdays(from series: [ScheduleEvent], calendar: Calendar) -> Set<Int> {
        let counts = Dictionary(grouping: series) { calendar.component(.weekday, from: $0.start) }
            .mapValues(\.count)
        guard let highest = counts.values.max() else { return [] }
        let threshold = max(2, highest / 2)
        return Set(counts.compactMap { $0.value >= threshold ? $0.key : nil })
    }

    private static func weeklyTemplate(from series: [ScheduleEvent], calendar: Calendar) -> WeeklyTemplate? {
        var counts: [WeeklyTemplate: Int] = [:]
        let ordered = series.sorted { $0.start < $1.start }
        for event in ordered {
            counts[weeklyTemplate(event, calendar: calendar), default: 0] += 1
        }
        guard let highest = counts.values.max() else { return nil }
        return ordered.lazy.map { weeklyTemplate($0, calendar: calendar) }
            .first { counts[$0] == highest }
    }

    private static func weeklyTemplate(_ event: ScheduleEvent, calendar: Calendar) -> WeeklyTemplate {
        WeeklyTemplate(
            title: event.title, location: event.location, notes: event.notes,
            reminderMinutes: event.reminderMinutes, reminderMinutes2: event.reminderMinutes2,
            pinned: event.pinned, source: event.source,
            hour: calendar.component(.hour, from: event.start),
            minute: calendar.component(.minute, from: event.start),
            durationSeconds: max(0, Int(event.end.timeIntervalSince(event.start).rounded()))
        )
    }

    /// 단일 회차 편집을 독립적으로 저장한다. source 톰스톤은 저장 성공 후에만 기록한다.
    @discardableResult
    static func update(
        _ event: ScheduleEvent,
        title: String, start: Date, end: Date, location: String, notes: String,
        reminderMinutes: Int, reminderMinutes2: Int, pinned: Bool,
        in context: ModelContext
    ) -> Bool {
        let original = EditableSnapshot(event)
        event.title = title
        event.location = location
        event.start = start
        event.end = end
        event.reminderMinutes = reminderMinutes
        event.reminderMinutes2 = reminderMinutes2
        event.pinned = pinned
        event.notes = notes
        event.source = ""
        do {
            try context.save()
            SourceTombstones.record(source: original.source, title: original.title, start: original.start)
            return true
        } catch {
            original.restore(event)
            return false
        }
    }

    @discardableResult
    static func deleteSingle(_ event: ScheduleEvent, in context: ModelContext) -> Bool {
        let tombstone = (event.source, event.title, event.start)
        context.delete(event)
        do {
            try context.save()
            SourceTombstones.record(source: tombstone.0, title: tombstone.1, start: tombstone.2)
            return true
        } catch {
            context.insert(event)
            return false
        }
    }

    /// 앱이 만든 특정 출처(timetable/academic)의 내용 중복 제거.
    /// 여러 기기에서 각자 임포트 → CloudKit 병합으로 동일 일정이 두 벌 생기거나, 삭제가 동기화되기 전
    /// 재생성돼 좀비 레코드가 남는 경우를 정리한다. 사용자 일정(source="")은 절대 건드리지 않는다.
    static func dedupBySource(_ sources: Set<String>, in context: ModelContext) {
        guard let changed = try? stageDedupBySource(sources, in: context) else { return }
        if changed { try? context.save() }
    }

    /// 기존 출처 일정 삭제와 새 일정 생성을 격리된 컨텍스트에서 한 번에 저장한다.
    static func replaceSources<Output>(
        _ sources: Set<String>, in context: ModelContext,
        build: (ModelContext) throws -> Output
    ) throws -> Output {
        let replacement = ModelContext(context.container)
        replacement.autosaveEnabled = false
        do {
            for source in sources {
                let descriptor = FetchDescriptor<ScheduleEvent>(
                    predicate: #Predicate<ScheduleEvent> { $0.source == source }
                )
                for event in try replacement.fetch(descriptor) { replacement.delete(event) }
            }
            let result = try build(replacement)
            _ = try stageDedupBySource(sources, in: replacement)
            try replacement.save()
            return result
        } catch {
            replacement.rollback()
            throw error
        }
    }

    private static func stageDedupBySource(_ sources: Set<String>, in context: ModelContext) throws -> Bool {
        let all = try context.fetch(FetchDescriptor<ScheduleEvent>())
        var seen = Set<String>()
        var changed = false
        for e in all where sources.contains(e.source) {
            let key = "\(e.source)|\(e.title)|\(Int(e.start.timeIntervalSince1970))|\(Int(e.end.timeIntervalSince1970))"
            if !seen.insert(key).inserted { context.delete(e); changed = true }   // 같은 (출처·제목·시작·끝) → 하나만 남김
        }
        return changed
    }

    /// 특정 출처(timetable/academic)의 일정 전부 삭제. 재가져오기 전 호출.
    static func deleteBySource(_ source: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<ScheduleEvent>(
            predicate: #Predicate<ScheduleEvent> { $0.source == source }
        )
        if let items = try? context.fetch(descriptor) {
            for e in items { context.delete(e) }
        }
        try? context.save()
    }

    /// 반복 시리즈 편집(이후 회차 전체): 이후 회차 삭제(원본 자리 톰스톤 기록) 후 새 규칙으로 재생성.
    /// 재생성분은 반드시 사용자 소유(source "")로 claim — 원래 source("timetable")를 그대로 쓰면
    /// ① 방금 기록한 톰스톤이 재생성을 막아 시리즈가 통째로 증발하고(제목·시각 동일 시),
    /// ② 살아남아도 다음 NEIS 자동 갱신(deleteBySource)이 편집 내용을 지워 원복한다.
    /// 원본 자리 톰스톤은 남겨 자동 갱신이 원래 수업을 되살리지 않게 한다(진짜 삭제와 동일 의미).
    @discardableResult
    static func editFutureSeries(
        from event: ScheduleEvent,
        title: String, start: Date, end: Date, location: String, notes: String = "",
        reminderMinutes: Int, reminderMinutes2: Int = -1, recurrence: Recurrence,
        weekdays: Set<Int> = [], endDate: Date? = nil, pinned: Bool = false,
        in context: ModelContext
    ) -> Bool {
        guard let deletion = stageDeleteFutureSeries(from: event, in: context) else { return false }
        let inserted = stageCreate(
            title: title, start: start, end: end, location: location, notes: notes,
            reminderMinutes: reminderMinutes, reminderMinutes2: reminderMinutes2,
            recurrence: recurrence, weekdays: weekdays, endDate: endDate,
            source: "", pinned: pinned, into: context)
        do {
            try context.save()
            recordTombstones(deletion.tombstones)
            return true
        } catch {
            for event in inserted { context.delete(event) }
            restore(deletion, in: context)
            return false
        }
    }

    /// 이 일정 + 같은 시리즈의 이후(시작 ≥) 일정 모두 삭제.
    @discardableResult
    static func deleteFutureSeries(from event: ScheduleEvent, in context: ModelContext) -> Bool {
        guard let deletion = stageDeleteFutureSeries(from: event, in: context) else { return false }
        do {
            try context.save()
            recordTombstones(deletion.tombstones)
            return true
        } catch {
            restore(deletion, in: context)
            return false
        }
    }

    private typealias Tombstone = (source: String, title: String, start: Date)
    private struct StagedDeletion {
        var deleted: [ScheduleEvent] = []
        var closed: [(event: ScheduleEvent, generatedThrough: Date?)] = []
        var tombstones: [Tombstone] = []
    }

    private static func stageDeleteFutureSeries(
        from event: ScheduleEvent, in context: ModelContext
    ) -> StagedDeletion? {
        let sid = event.seriesID
        guard !sid.isEmpty else {
            let tombstone = (event.source, event.title, event.start)
            context.delete(event)
            return StagedDeletion(
                deleted: [event],
                tombstones: [tombstone])
        }
        let start = event.start
        let descriptor = FetchDescriptor<ScheduleEvent>(
            predicate: #Predicate<ScheduleEvent> { $0.seriesID == sid }
        )
        let items: [ScheduleEvent]
        do { items = try context.fetch(descriptor) }
        catch { return nil }

        var deletion = StagedDeletion()
        if !items.isEmpty {
            for e in items {
                if e.start >= start {
                    deletion.deleted.append(e)
                    deletion.tombstones.append((e.source, e.title, e.start))
                    context.delete(e)
                } else {
                    deletion.closed.append((e, e.recurrenceGeneratedThrough))
                    e.recurrenceGeneratedThrough = nil   // 남은 과거 회차가 삭제한 미래를 다시 보충하지 않게 시리즈 닫기
                }
            }
        } else {
            deletion.deleted.append(event)
            deletion.tombstones.append((event.source, event.title, event.start))
            context.delete(event)
        }
        return deletion
    }

    private static func restore(_ deletion: StagedDeletion, in context: ModelContext) {
        for item in deletion.closed {
            item.event.recurrenceGeneratedThrough = item.generatedThrough
        }
        for event in deletion.deleted { context.insert(event) }
    }

    private static func recordTombstones(_ tombstones: [Tombstone]) {
        for tombstone in tombstones {
            SourceTombstones.record(source: tombstone.source, title: tombstone.title, start: tombstone.start)
        }
    }
}
