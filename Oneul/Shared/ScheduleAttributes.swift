import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity 한 칸(일정)의 스냅샷.
/// SwiftData 모델(`ScheduleEvent`)과 별개로, 위젯에 넘기기 위한 가벼운 값 타입입니다.
struct EventSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    /// 무지개 팔레트 인덱스(시간 순서대로 0,1,2…). 색은 인덱스로만 전달합니다.
    var colorIndex: Int
    /// 이틀 이상 걸치는 일정(바 위 흰 밴드로 표시).
    var isMultiDay: Bool = false
}

#if canImport(ActivityKit)
/// 잠금화면 + 다이나믹 아일랜드 Live Activity의 데이터 정의.
/// - `attributes`(고정): 그날 라벨
/// - `ContentState`(갱신): 그날 일정 목록 + 현재/다음 일정
struct ScheduleActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 바가 표현하는 하루의 시작/끝(보통 첫 일정 ~ 마지막 일정, 패딩 포함).
        var dayStart: Date
        var dayEnd: Date
        /// 그날 일정들(시간 순, colorIndex 부여됨).
        var segments: [EventSnapshot]

        /// 지금 진행 중인 일정(없으면 nil).
        var currentTitle: String?
        var currentEnd: Date?
        /// 다음 일정(없으면 nil).
        var nextTitle: String?
        var nextStart: Date?
    }

    /// 예: "6월 17일 화요일"
    var dayLabel: String
}
#endif

/// 일정들을 빈틈없이 붙여 바를 채우는 레이아웃 + 진행 위치 계산.
/// (앱·위젯 공통) 진행 중이면 그 칸 안 비율, 쉬는 시간엔 다음 칸 경계에 정지.
struct PackedLayout {
    struct Slot { let left: Double; let width: Double }   // 0...1

    let slots: [Slot]
    private let intervals: [(start: Date, end: Date)]

    init(intervals: [(start: Date, end: Date)], minWidth: Double = 0.05) {
        self.intervals = intervals
        guard !intervals.isEmpty else { slots = []; return }

        let durations = intervals.map { max(1, $0.end.timeIntervalSince($0.start)) }
        let total = durations.reduce(0, +)
        var widths = durations.map { max($0 / total, minWidth) }
        let sum = widths.reduce(0, +)
        widths = widths.map { $0 / sum }

        var acc = 0.0
        slots = widths.map { w in
            let slot = Slot(left: acc, width: w)
            acc += w
            return slot
        }
    }

    /// 진행 위치(0...1). 쉬는 시간엔 다음 칸 경계에 정지.
    func fraction(at now: Date) -> Double {
        guard !intervals.isEmpty else { return 0 }
        if now < intervals[0].start { return 0 }
        for i in intervals.indices {
            let iv = intervals[i]
            if now < iv.start { return slots[i].left }     // 쉬는 시간 → 경계 정지
            if now < iv.end {
                let f = now.timeIntervalSince(iv.start) / iv.end.timeIntervalSince(iv.start)
                return slots[i].left + slots[i].width * f  // 진행 중
            }
        }
        return 1
    }

    /// 지금이 쉬는 시간(어떤 일정에도 안 속하고 다음 일정이 남음)인지.
    func isWaiting(at now: Date) -> Bool {
        guard let first = intervals.first, let last = intervals.last else { return false }
        if now < first.start || now >= last.end { return false }
        return !intervals.contains { now >= $0.start && now < $0.end }
    }
}
