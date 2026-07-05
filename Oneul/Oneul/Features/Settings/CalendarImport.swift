import Foundation
import EventKit
import SwiftData

/// 애플 캘린더(EventKit) → Oneul 일회성 가져오기. 오늘부터 90일, (제목·시작) 중복은 건너뜀.
enum CalendarImport {
    enum ImportError: Error { case denied }

    static func run(context: ModelContext) async throws -> Int {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw ImportError.denied }

        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 90, to: start) ?? start
        let ekEvents = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))

        let existing = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
        var seen = Set(existing.map { "\($0.title)|\(Int($0.start.timeIntervalSince1970))" })
        var added = 0
        for ek in ekEvents {
            guard let s = ek.startDate, let e = ek.endDate else { continue }
            let title = ek.title ?? ""
            let key = "\(title)|\(Int(s.timeIntervalSince1970))"
            guard seen.insert(key).inserted else { continue }
            context.insert(ScheduleEvent(title: title, start: s, end: e,
                                         location: ek.location ?? "", reminderMinutes: -1))
            added += 1
        }
        try? context.save()
        return added
    }
}
