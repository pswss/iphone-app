// 실행: xcrun swiftc -parse-as-library Shared/AppConfig.swift Shared/ScheduleAttributes.swift harness/RemainingTimeHarness.swift -o /tmp/oneul-remaining-time && /tmp/oneul-remaining-time
import Foundation

@main
struct RemainingTimeHarness {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        assert(longEventRemainingLabel(until: now.addingTimeInterval(48 * 3_600), now: now, english: false) == "남은 2일")
        assert(longEventRemainingLabel(until: now.addingTimeInterval(25 * 3_600), now: now, english: true) == "1 day left")
        assert(longEventRemainingLabel(until: now.addingTimeInterval(23 * 3_600 + 3_599), now: now, english: true) == "23 hours left")
        assert(longEventRemainingLabel(until: now.addingTimeInterval(30 * 60), now: now, english: false) == "남은 1시간")

        assert(remainingLabel(to: now.addingTimeInterval(3_601), english: false, now: now) == "1시간")
        assert(remainingLabel(to: now.addingTimeInterval(125), english: true, now: now) == "2 min")

        let first = EventSnapshot(id: UUID(), title: "첫 일정",
                                  start: now.addingTimeInterval(65), end: now.addingTimeInterval(125), colorIndex: 0)
        let second = EventSnapshot(id: UUID(), title: "다음 일정",
                                   start: now.addingTimeInterval(185), end: now.addingTimeInterval(245), colorIndex: 1)
        let long = EventSnapshot(id: UUID(), title: "멀티데이",
                                 start: now.addingTimeInterval(-100), end: now.addingTimeInterval(500),
                                 colorIndex: 2, isMultiDay: true)
        let events = [long, second, first]

        assert(events.glanceStatus(at: now).next?.title == first.title)
        assert(events.glanceStatus(at: first.start).current?.title == first.title)
        assert(events.glanceStatus(at: first.end).next?.title == second.title)
        assert([long].glanceStatus(at: now).current?.title == long.title)

        let dates = events.glanceTimelineDates(from: now)
        assert(dates.contains(first.start))                     // 대기 → 진행 중
        assert(dates.contains(first.end))                       // 진행 중 → 다음 대기
        assert(dates.contains(second.start))
        assert(dates.contains(second.end))

        let near = EventSnapshot(id: UUID(), title: "30분 뒤", start: now.addingTimeInterval(1_800),
                                 end: now.addingTimeInterval(2_000), colorIndex: 0)
        assert([near].glanceTimelineDates(from: now)[1] == now.addingTimeInterval(300))
        let far = EventSnapshot(id: UUID(), title: "2시간 뒤", start: now.addingTimeInterval(7_200),
                                end: now.addingTimeInterval(7_400), colorIndex: 0)
        assert([far].glanceTimelineDates(from: now)[1] == now.addingTimeInterval(3_600))
        assert([EventSnapshot]().glanceTimelineDates(from: now) == [now])

        let compact = (0..<12).map { index in
            GlanceEventSnapshot(title: "일정 \(index)", start: now.addingTimeInterval(Double(index * 600)),
                                end: now.addingTimeInterval(Double(index * 600 + 300)))
        }
        assert(compact.glanceStatus(at: now.addingTimeInterval(6_060)).current?.title == "일정 10")
        print("ALL PASS")
    }
}
