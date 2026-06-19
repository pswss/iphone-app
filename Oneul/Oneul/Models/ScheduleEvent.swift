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
    /// Recurrence.rawValue ("none"/"daily"/…).
    var recurrenceRaw: String = "none"
    /// 반복 시리즈 식별자. 빈 값이면 단일 일정.
    var seriesID: String = ""

    init(
        id: UUID = UUID(),
        title: String = "",
        start: Date = .now,
        end: Date = .now,
        location: String = "",
        notes: String = "",
        reminderMinutes: Int = 10,
        recurrenceRaw: String = "none",
        seriesID: String = ""
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.recurrenceRaw = recurrenceRaw
        self.seriesID = seriesID
    }
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

// MARK: - 생성/삭제 동작

enum EventActions {
    /// 일정 생성.
    /// - 반복이 매주이고 `weekdays`(1=일…7=토)가 있으면 그 요일마다 생성.
    /// - `endDate`가 있으면 그날까지, 없으면 1년(최대 800개)까지.
    static func create(
        title: String, start: Date, end: Date, location: String,
        reminderMinutes: Int, recurrence: Recurrence,
        weekdays: Set<Int> = [], endDate: Date? = nil, into context: ModelContext
    ) {
        let duration = max(0, end.timeIntervalSince(start))

        guard recurrence != .none else {
            context.insert(ScheduleEvent(title: title, start: start, end: end,
                                         location: location, reminderMinutes: reminderMinutes))
            try? context.save()
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
                if weekdays.contains(cal.component(.weekday, from: day)),
                   let s = cal.date(bySettingHour: h, minute: m, second: 0, of: day), s >= start {
                    context.insert(ScheduleEvent(
                        title: title, start: s, end: s.addingTimeInterval(duration),
                        location: location, reminderMinutes: reminderMinutes,
                        recurrenceRaw: recurrence.rawValue, seriesID: seriesID))
                    count += 1
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        } else if let step = recurrence.step {
            var date = start
            while date <= horizon && count < cap {
                context.insert(ScheduleEvent(
                    title: title, start: date, end: date.addingTimeInterval(duration),
                    location: location, reminderMinutes: reminderMinutes,
                    recurrenceRaw: recurrence.rawValue, seriesID: seriesID))
                count += 1
                guard let next = cal.date(byAdding: step.component, value: step.value, to: date) else { break }
                date = next
            }
        }
        try? context.save()
    }

    static func deleteSingle(_ event: ScheduleEvent, in context: ModelContext) {
        context.delete(event)
        try? context.save()
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
            for e in items { context.delete(e) }
        } else {
            context.delete(event)
        }
        try? context.save()
    }
}
