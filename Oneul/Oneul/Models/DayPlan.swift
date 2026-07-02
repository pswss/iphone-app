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

    /// 그날 하루 안에서 시작·종료하는 일정 (무지개 바 패킹 대상).
    var singleDayEvents: [ScheduleEvent] { events.filter { !$0.isMultiDay() } }
    /// 이틀 이상 걸치는 일정 (바 상단 흰 글로우 밴드 대상).
    var multiDayEvents: [ScheduleEvent] { events.filter { $0.isMultiDay() } }

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

    /// Live Activity로 넘길 스냅샷 묶음.
    func contentState(at now: Date = .now) -> ScheduleActivityAttributes.ContentState {
        let snaps = events.enumerated().map { index, e in
            EventSnapshot(id: e.id, title: e.title, start: e.start, end: e.end,
                          colorIndex: index, isMultiDay: e.isMultiDay())
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

    /// 애플워치로 보낼 오늘 일정 스냅샷.
    func watchPayload(dayLabel: String, at now: Date = .now) -> WatchSchedulePayload {
        let snaps = events.enumerated().map { index, e in
            EventSnapshot(id: e.id, title: e.title, start: e.start, end: e.end,
                          colorIndex: index, isMultiDay: e.isMultiDay())
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
        let s = contentState(at: now)
        return HomeSnapshot(
            dayLabel: dayLabel, dayStart: s.dayStart, dayEnd: s.dayEnd, segments: s.segments,
            currentTitle: s.currentTitle, currentEnd: s.currentEnd,
            nextTitle: s.nextTitle, nextStart: s.nextStart, isEnglish: s.isEnglish, updatedAt: now)
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
        return lunarHolidays(year: y, cal: cal)[cal.startOfDay(for: day)]
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
