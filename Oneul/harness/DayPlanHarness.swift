// DayPlan priority/color harness. Compile with DayPlan.swift + ScheduleEvent.swift;
// lightweight snapshot/palette types below avoid pulling every app target into this check.
import Foundation
import SwiftUI

final class AppLanguage {
    static let shared = AppLanguage()
    let isEnglish = false
}

enum EventPalette {
    static func color(_ index: Int) -> Color { fatalError("고정색 경로 사용") }
    static func color(_ index: Int, of total: Int) -> Color { .red }
}

struct EventSnapshot: Identifiable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var colorIndex: Int
    var isMultiDay = false
}

struct WatchSchedulePayload {
    var dayLabel: String
    var dayStart: Date
    var dayEnd: Date
    var events: [EventSnapshot]
    var currentTitle: String?
    var currentEnd: Date?
    var nextTitle: String?
    var nextStart: Date?
    var isEnglish = false
    var updatedAt: Date
}

struct HomeSnapshot {
    var dayLabel: String
    var dayStart: Date
    var dayEnd: Date
    var segments: [EventSnapshot]
    var currentTitle: String?
    var currentEnd: Date?
    var nextTitle: String?
    var nextStart: Date?
    var isEnglish = false
    var updatedAt = Date()
}

@main
struct DayPlanHarness {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: day, hour: hour))!
    }

    static func event(_ title: String, _ start: Date, _ end: Date) -> ScheduleEvent {
        ScheduleEvent(title: title, start: start, end: end, reminderMinutes: -1)
    }

    static func main() {
        let now = date(24, 10).addingTimeInterval(30 * 60)
        let long = event("장기 진행", date(23, 8), date(25, 8))
        let marker = event("기념일", date(24, 0), date(24, 23))
        let current = event("당일 현재", date(24, 10), date(24, 11))
        let next = event("당일 다음", date(24, 12), date(24, 13))
        current.source = "timetable"
        next.source = "timetable"
        let plan = DayPlan(events: [long, marker, current, next], day: now, calendar: calendar)

        assert(plan.current(at: now)?.id == current.id)
        assert(plan.next(at: now)?.id == next.id)
        assert(plan.colorIndex(of: current) == 0)
        assert(plan.colorIndex(of: next) == 1)
        _ = plan.color(of: current)
        assert(plan.watchPayload(dayLabel: "").events.first { $0.id == current.id }?.colorIndex == 0)
        assert(plan.homeSnapshot(dayLabel: "").segments.first { $0.id == current.id }?.colorIndex == 0)

        let futureTimed = event("당일 예정", date(24, 12), date(24, 13))
        let mixed = DayPlan(events: [long, futureTimed], day: now, calendar: calendar)
        assert(mixed.current(at: now) == nil)
        assert(mixed.next(at: now)?.id == futureTimed.id)

        let futureLong = event("장기 다음", date(24, 16), date(25, 16))
        let fallback = DayPlan(events: [long, futureLong], day: now, calendar: calendar)
        assert(fallback.current(at: now)?.id == long.id)
        assert(fallback.next(at: now)?.id == futureLong.id)

        print("DayPlanHarness PASS")
    }
}
