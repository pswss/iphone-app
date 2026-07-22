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
        self.source = source
        self.pinned = pinned
    }
}

/// 시험 유형 (제목 키워드로 판별). 시험 1일 전 알림·준비물에 사용.
enum ExamKind {
    case none    // 시험 아님
    case school  // 내신 지필 + 모의고사 + 학력평가 — 시계·필기구만
    case csat    // 수능 — 수험표·신분증까지

    /// 준비물 체크리스트.
    var checklist: [String] {
        switch self {
        case .none: return []
        case .school: return ["시계", "필기구"]
        case .csat: return ["시계", "필기구", "수험표", "신분증"]
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
        // '시험공부'·'시험 준비'처럼 시험을 준비하는 일정은 시험 자체가 아님 → 전날 준비물 알림 오탐 방지
        let studyWords = ["공부", "준비", "대비", "복습", "특강", "학습"]
        if studyWords.contains(where: t.contains) { return .none }
        let isMock = t.contains("모의") || t.contains("학력평가") || t.contains("연합")
        if !isMock && (t.contains("수학능력시험") || t.contains("수능")) { return .csat }
        let school = ["모의", "학력평가", "연합", "지필", "중간고사", "기말고사", "고사", "시험", "평가"]
        if school.contains(where: t.contains) { return .school }
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
    /// 일정 생성.
    /// - 반복이 매주이고 `weekdays`(1=일…7=토)가 있으면 그 요일마다 생성.
    /// - `endDate`가 있으면 그날까지, 없으면 1년(최대 800개)까지.
    static func create(
        title: String, start: Date, end: Date, location: String,
        reminderMinutes: Int, reminderMinutes2: Int = -1, recurrence: Recurrence,
        weekdays: Set<Int> = [], endDate: Date? = nil, source: String = "",
        excludeDays: Set<Date> = [], pinned: Bool = false, into context: ModelContext
    ) {
        let duration = max(0, end.timeIntervalSince(start))

        guard recurrence != .none else {
            if !SourceTombstones.contains(source: source, title: title, start: start) {
                context.insert(ScheduleEvent(title: title, start: start, end: end,
                                             location: location, reminderMinutes: reminderMinutes,
                                             reminderMinutes2: reminderMinutes2, source: source, pinned: pinned))
                try? context.save()
            }
            return
        }

        let cal = Calendar.current
        let seriesID = UUID().uuidString
        let horizon = endDate ?? cal.date(byAdding: .year, value: 1, to: start) ?? start
        let cap = 800
        var count = 0

        if recurrence == .weekly && !weekdays.isEmpty {
            // 선택한 요일마다 매주, 종료일까지
            let h = cal.component(.hour, from: start)
            let m = cal.component(.minute, from: start)
            var day = cal.startOfDay(for: start)
            let endDay = cal.startOfDay(for: horizon)
            while day <= endDay && count < cap {
                if weekdays.contains(cal.component(.weekday, from: day)), !excludeDays.contains(day),
                   let s = cal.date(bySettingHour: h, minute: m, second: 0, of: day), s >= start,
                   !SourceTombstones.contains(source: source, title: title, start: s) {
                    context.insert(ScheduleEvent(
                        title: title, start: s, end: s.addingTimeInterval(duration),
                        location: location, reminderMinutes: reminderMinutes,
                        reminderMinutes2: reminderMinutes2,
                        recurrenceRaw: recurrence.rawValue, seriesID: seriesID, source: source, pinned: pinned))
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
                context.insert(ScheduleEvent(
                    title: title, start: date, end: date.addingTimeInterval(duration),
                    location: location, reminderMinutes: reminderMinutes,
                    reminderMinutes2: reminderMinutes2,
                    recurrenceRaw: recurrence.rawValue, seriesID: seriesID, source: source, pinned: pinned))
                count += 1
                guard let next = cal.date(byAdding: step.component, value: step.value, to: date) else { break }
                date = next
            }
        }
        try? context.save()
    }

    /// 시간표/학사일정(source != "") 일정을 사용자가 고치면: 원본 자리 톰스톤 기록 + source 비움.
    /// → 일일 자동 재가져오기가 이 일정을 지우지도, 원래 내용으로 되살리지도 않는다.
    static func claimFromSource(_ event: ScheduleEvent) {
        guard !event.source.isEmpty else { return }
        SourceTombstones.record(source: event.source, title: event.title, start: event.start)
        event.source = ""
    }

    static func deleteSingle(_ event: ScheduleEvent, in context: ModelContext) {
        SourceTombstones.record(source: event.source, title: event.title, start: event.start)   // 자동 갱신이 되살리지 않게
        context.delete(event)
        try? context.save()
    }

    /// 앱이 만든 특정 출처(timetable/academic)의 내용 중복 제거.
    /// 여러 기기에서 각자 임포트 → CloudKit 병합으로 동일 일정이 두 벌 생기거나, 삭제가 동기화되기 전
    /// 재생성돼 좀비 레코드가 남는 경우를 정리한다. 사용자 일정(source="")은 절대 건드리지 않는다.
    static func dedupBySource(_ sources: Set<String>, in context: ModelContext) {
        guard let all = try? context.fetch(FetchDescriptor<ScheduleEvent>()) else { return }
        var seen = Set<String>()
        var changed = false
        for e in all where sources.contains(e.source) {
            let key = "\(e.source)|\(e.title)|\(Int(e.start.timeIntervalSince1970))|\(Int(e.end.timeIntervalSince1970))"
            if !seen.insert(key).inserted { context.delete(e); changed = true }   // 같은 (출처·제목·시작·끝) → 하나만 남김
        }
        if changed { try? context.save() }
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
    static func editFutureSeries(
        from event: ScheduleEvent,
        title: String, start: Date, end: Date, location: String,
        reminderMinutes: Int, reminderMinutes2: Int = -1, recurrence: Recurrence,
        weekdays: Set<Int> = [], endDate: Date? = nil, pinned: Bool = false,
        in context: ModelContext
    ) {
        deleteFutureSeries(from: event, in: context)
        create(title: title, start: start, end: end, location: location,
               reminderMinutes: reminderMinutes, reminderMinutes2: reminderMinutes2,
               recurrence: recurrence, weekdays: weekdays, endDate: endDate,
               source: "", pinned: pinned, into: context)
    }

    /// 이 일정 + 같은 시리즈의 이후(시작 ≥) 일정 모두 삭제.
    static func deleteFutureSeries(from event: ScheduleEvent, in context: ModelContext) {
        let sid = event.seriesID
        guard !sid.isEmpty else { deleteSingle(event, in: context); return }
        let start = event.start
        let descriptor = FetchDescriptor<ScheduleEvent>(
            predicate: #Predicate<ScheduleEvent> { $0.seriesID == sid && $0.start >= start }
        )
        if let items = try? context.fetch(descriptor), !items.isEmpty {
            for e in items {
                SourceTombstones.record(source: e.source, title: e.title, start: e.start)
                context.delete(e)
            }
        } else {
            SourceTombstones.record(source: event.source, title: event.title, start: event.start)
            context.delete(event)
        }
        try? context.save()
    }
}
