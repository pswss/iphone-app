import Foundation

/// 하루치 일정을 받아 무지개 바/Live Activity에 필요한 값들을 계산하는 순수 로직.
/// UI·위젯·Live Activity가 모두 같은 규칙(색=시간순, 현재/다음 판정)을 쓰도록 한 곳에 모읍니다.
struct DayPlan {
    /// 시간 순으로 정렬된 일정(색 인덱스 = 배열 인덱스).
    let events: [ScheduleEvent]
    /// 바가 그릴 하루 범위.
    let dayStart: Date
    let dayEnd: Date

    init(events: [ScheduleEvent], day: Date = .now, calendar: Calendar = .current) {
        let todays = events
            .filter { $0.occurs(on: day, calendar: calendar) }
            .sorted { $0.start < $1.start }
        self.events = todays

        // 바 범위: 첫 일정 시작 ~ 마지막 일정 끝(양쪽 30분 패딩). 일정이 없으면 9~18시.
        // 멀티데이 일정은 이 날짜 범위(자정~자정)로 클램프해 바가 며칠로 늘어나지 않게.
        let midnight = calendar.startOfDay(for: day)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight) ?? midnight
        if !todays.isEmpty {
            let first = todays.map { max($0.start, midnight) }.min() ?? midnight
            let last = todays.map { min($0.end, nextMidnight) }.max() ?? nextMidnight
            self.dayStart = first.addingTimeInterval(-30 * 60)
            self.dayEnd = max(last, first.addingTimeInterval(60 * 60)).addingTimeInterval(30 * 60)
        } else {
            let base = calendar.startOfDay(for: day)
            self.dayStart = calendar.date(byAdding: .hour, value: 9, to: base) ?? base
            self.dayEnd = calendar.date(byAdding: .hour, value: 18, to: base) ?? base
        }
    }

    var isEmpty: Bool { events.isEmpty }

    /// 오늘부터 가장 가까운, 일정이 있는 날의 플랜(없으면 nil).
    /// Live Activity가 오늘이 비어도 다가오는 일정을 보여주도록.
    static func upcoming(events: [ScheduleEvent], within days: Int = 14,
                         now: Date = .now, calendar: Calendar = .current) -> (plan: DayPlan, day: Date)? {
        for off in 0..<days {
            guard let d = calendar.date(byAdding: .day, value: off, to: now) else { continue }
            let p = DayPlan(events: events, day: d)
            if !p.isEmpty { return (p, d) }
        }
        return nil
    }

    /// 그날 하루 안의 시간제 일정 (무지개 바·그리드 블록 대상). 생일·기념일 같은 데이마커는 제외.
    var singleDayEvents: [ScheduleEvent] { events.filter { !$0.isMultiDay() && !$0.isDayMarker() } }
    /// 종일 배너 대상 — 이틀 이상 걸치는 일정 + 하루짜리 데이마커(생일·기념일·종일격).
    var multiDayEvents: [ScheduleEvent] { events.filter { $0.isMultiDay() || $0.isDayMarker() } }

    /// 0...1 사이의 가로 위치(바 안에서의 비율).
    func fraction(for date: Date) -> Double {
        let total = dayEnd.timeIntervalSince(dayStart)
        guard total > 0 else { return 0 }
        let x = date.timeIntervalSince(dayStart) / total
        return min(max(x, 0), 1)
    }

    /// 지금 진행 중인 일정.
    func current(at now: Date = .now) -> ScheduleEvent? {
        events.first { now >= $0.start && now < $0.end }
    }

    /// 아직 시작 안 한 다음 일정.
    func next(at now: Date = .now) -> ScheduleEvent? {
        events.first { $0.start > now }
    }

    /// 색 인덱스(시간 순서).
    func colorIndex(of event: ScheduleEvent) -> Int {
        events.firstIndex(where: { $0.id == event.id }) ?? 0
    }

    #if os(iOS)
    /// Live Activity로 넘길 스냅샷 묶음(ActivityKit 런타임이 있는 iOS에서만 — macOS엔 없음).
    /// ActivityKit 콘텐츠는 4KB 제한 — 초과하면 'ActivityInput error 0'으로 시작 실패.
    /// 시간표로 이벤트가 많은 날을 위해 스냅샷 개수·제목 길이를 캡.
    func contentState(at now: Date = .now) -> ScheduleActivityAttributes.ContentState {
        let cap = 10
        // 하루 전체가 바에 보이게(지난 칸은 렌더러가 흐리게 그림) — 캡 초과 시 미래 우선,
        // 남는 자리는 최근에 끝난 일정부터 채움. 끝난 일정을 통째로 빼면 바가 남은 일정만 보인다.
        let past = events.filter { $0.end < now }
        let upcoming = events.filter { $0.end >= now }
        let futurePick = Array(upcoming.prefix(cap))
        let picked = Array(past.suffix(cap - futurePick.count)) + futurePick
        let snaps = picked.map { e in
            EventSnapshot(id: e.id, title: String(e.title.prefix(16)), start: e.start, end: e.end,
                          colorIndex: colorIndex(of: e), isMultiDay: e.isMultiDay() || e.isDayMarker())
        }
        let cur = current(at: now)
        let nxt = next(at: now)
        return .init(
            dayStart: dayStart,
            dayEnd: dayEnd,
            segments: snaps,
            currentTitle: cur?.title,
            currentEnd: cur?.end,
            nextTitle: nxt?.title,
            nextStart: nxt?.start,
            isEnglish: AppLanguage.shared.isEnglish
        )
    }
    #endif

    /// 애플워치로 보낼 오늘 일정 스냅샷.
    func watchPayload(dayLabel: String, at now: Date = .now) -> WatchSchedulePayload {
        let snaps = events.enumerated().map { index, e in
            EventSnapshot(id: e.id, title: e.title, start: e.start, end: e.end,
                          colorIndex: index, isMultiDay: e.isMultiDay() || e.isDayMarker())
        }
        let cur = current(at: now)
        let nxt = next(at: now)
        return WatchSchedulePayload(
            dayLabel: dayLabel, dayStart: dayStart, dayEnd: dayEnd, events: snaps,
            currentTitle: cur?.title, currentEnd: cur?.end,
            nextTitle: nxt?.title, nextStart: nxt?.start, updatedAt: now)
    }

    /// 홈 화면 위젯으로 넘길 오늘 스냅샷(App Group 공유). contentState()와 같은 값을 ActivityKit 비의존 형태로.
    func homeSnapshot(dayLabel: String, at now: Date = .now) -> HomeSnapshot {
        let snaps = events.enumerated().map { index, e in
            EventSnapshot(id: e.id, title: e.title, start: e.start, end: e.end,
                          colorIndex: index, isMultiDay: e.isMultiDay() || e.isDayMarker())
        }
        let cur = current(at: now)
        let nxt = next(at: now)
        return HomeSnapshot(
            dayLabel: dayLabel, dayStart: dayStart, dayEnd: dayEnd, segments: snaps,
            currentTitle: cur?.title, currentEnd: cur?.end,
            nextTitle: nxt?.title, nextStart: nxt?.start,
            isEnglish: AppLanguage.shared.isEnglish, updatedAt: now)
    }
}

// MARK: - 공휴일 (양력 + 음력 설날/추석/부처님오신날)

enum Holidays {
    /// 공휴일 이름(없으면 nil).
    static func name(for day: Date) -> String? {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: day)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        if let s = solar["\(m)-\(d)"] { return s }
        if let l = lunarHolidays(year: y, cal: cal)[cal.startOfDay(for: day)] { return l }
        return substituteName(for: day, cal: cal)
    }

    /// 대체공휴일 — 「관공서의 공휴일에 관한 규정」 2023 개정 기준:
    /// · 삼일절·어린이날·광복절·개천절·한글날·부처님오신날·기독탄신일(크리스마스):
    ///   토요일·일요일과 겹치면 그다음 첫 평일(월요일)이 대체공휴일.
    /// · 설·추석 연휴(전날~다음날): 일요일과 겹칠 때만 연휴 다음 날이 대체공휴일(토요일 겹침은 대체 없음).
    /// · 신정·현충일: 대체공휴일 없음.
    // ponytail: 공휴일끼리 겹치는 해(예: 2025 어린이날=부처님오신날)의 연쇄 대체는 미처리 — 필요해지면 겹침 검사 추가
    private static func substituteName(for day: Date, cal: Calendar) -> String? {
        let wd = cal.component(.weekday, from: day)
        guard wd != 1, wd != 7 else { return nil }   // 대체일은 평일에만 생긴다

        // 토·일 겹침 대체(단일 공휴일) — 월요일에서 어제(일)·그제(토)를 본다
        if wd == 2 {
            let noSub: Set<String> = ["신정", "현충일"]
            for back in 1...2 {
                guard let prev = cal.date(byAdding: .day, value: -back, to: day) else { continue }
                let pc = cal.dateComponents([.month, .day], from: prev)
                if let name = solar["\(pc.month ?? 0)-\(pc.day ?? 0)"], !noSub.contains(name) {
                    return "대체공휴일(\(name))"
                }
                if lunarName(prev, cal: cal) == "부처님오신날" { return "대체공휴일(부처님오신날)" }
            }
        }

        // 설·추석: 어제가 연휴 마지막 날이고 연휴 3일 중 일요일이 있으면 오늘이 대체공휴일
        if let prev = cal.date(byAdding: .day, value: -1, to: day),
           let name = lunarName(prev, cal: cal), name == "설날" || name == "추석" {
            var d = prev
            var hitsSunday = false
            while lunarName(d, cal: cal) == name {
                if cal.component(.weekday, from: d) == 1 { hitsSunday = true }
                guard let p = cal.date(byAdding: .day, value: -1, to: d) else { break }
                d = p
            }
            if hitsSunday { return "대체공휴일(\(name))" }
        }
        return nil
    }

    private static func lunarName(_ day: Date, cal: Calendar) -> String? {
        lunarHolidays(year: cal.component(.year, from: day), cal: cal)[cal.startOfDay(for: day)]
    }

    static func isRed(_ day: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: day) == 1 || name(for: day) != nil
    }

    private static let solar: [String: String] = [
        "1-1": "신정", "3-1": "삼일절", "5-5": "어린이날", "6-6": "현충일",
        "8-15": "광복절", "10-3": "개천절", "10-9": "한글날", "12-25": "크리스마스"
    ]

    private static var lunarCache: [Int: [Date: String]] = [:]
    private static func lunarHolidays(year: Int, cal: Calendar) -> [Date: String] {
        if let cached = lunarCache[year] { return cached }
        var map: [Date: String] = [:]
        func add(_ name: String, lunarMonth m: Int, day d: Int, spread: Int) {
            guard let base = gregorian(lunarMonth: m, day: d, year: year, cal: cal) else { return }
            for off in -spread...spread {
                if let dd = cal.date(byAdding: .day, value: off, to: base) {
                    map[cal.startOfDay(for: dd)] = name
                }
            }
        }
        add("설날", lunarMonth: 1, day: 1, spread: 1)
        add("추석", lunarMonth: 8, day: 15, spread: 1)
        add("부처님오신날", lunarMonth: 4, day: 8, spread: 0)
        lunarCache[year] = map
        return map
    }

    private static func gregorian(lunarMonth m: Int, day: Int, year: Int, cal: Calendar) -> Date? {
        let chinese = Calendar(identifier: .chinese)
        guard var d = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year, month: 12, day: 31)) else { return nil }
        while d <= end {
            let lc = chinese.dateComponents([.month, .day], from: d)
            if lc.month == m && lc.day == day && !(lc.isLeapMonth ?? false) { return d }
            guard let nd = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = nd
        }
        return nil
    }
}
