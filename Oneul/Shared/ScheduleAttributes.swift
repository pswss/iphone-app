import Foundation
#if os(iOS)
import ActivityKit
#endif

/// 진행 중인 장기 일정의 거친 남은 시간: 24시간 이상은 일, 미만은 시간.
func longEventRemainingLabel(until end: Date, now: Date = .now, english: Bool) -> String {
    let seconds = max(0, end.timeIntervalSince(now))
    let amount: String
    if seconds >= 86_400 {
        let days = Int(seconds / 86_400)
        amount = english ? "\(days) \(days == 1 ? "day" : "days")" : "\(days)일"
    } else {
        let hours = seconds > 0 ? max(1, Int(seconds / 3_600)) : 0
        amount = english ? "\(hours) \(hours == 1 ? "hour" : "hours")" : "\(hours)시간"
    }
    return english ? "\(amount) left" : "남은 \(amount)"
}

/// 확장 화면 공용 남은 시간 표기. 초는 보이지 않고 기존 n시간/n분 형식을 유지한다.
func remainingLabel(to target: Date, english: Bool, now: Date = .now) -> String {
    let seconds = target.timeIntervalSince(now)
    if seconds <= 0 { return english ? "soon" : "곧" }
    let minutes = Int(seconds) / 60
    if minutes < 1 { return english ? "< 1 min" : "< 1분" }
    if minutes < 60 { return english ? "\(minutes) min" : "\(minutes)분" }
    return english ? "\(Int(seconds) / 3_600) hr" : "\(Int(seconds) / 3_600)시간"
}

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

/// Live Activity 상태 판정 전용 compact 일정. 4KB payload를 위해 색·UUID를 싣지 않는다.
struct GlanceEventSnapshot: Codable, Hashable {
    var title: String
    var start: Date
    var end: Date
    var isMultiDay: Bool = false
}

/// 저장 당시 current/next 문자열 대신 일정 시각에서 다시 계산한 확장 화면 상태.
struct GlanceStatus {
    let current: GlanceEventSnapshot?
    let next: GlanceEventSnapshot?
}

extension Array where Element == EventSnapshot {
    private var glanceEvents: [GlanceEventSnapshot] {
        map { GlanceEventSnapshot(title: $0.title, start: $0.start, end: $0.end, isMultiDay: $0.isMultiDay) }
    }

    func glanceStatus(at now: Date) -> GlanceStatus { glanceEvents.glanceStatus(at: now) }

    func glanceTimelineDates(from now: Date, limit: Int = 64) -> [Date] {
        glanceEvents.glanceTimelineDates(from: now, limit: limit)
    }
}

extension Array where Element == GlanceEventSnapshot {
    /// DayPlan과 같은 규칙: 당일 시간제 일정을 우선하고, 없을 때만 멀티데이 일정을 사용한다.
    func glanceStatus(at now: Date) -> GlanceStatus {
        let ordered = sorted { $0.start < $1.start }
        let timed = ordered.filter { !$0.isMultiDay }
        let statusEvents = timed.isEmpty ? ordered : timed
        return GlanceStatus(
            current: statusEvents.first { now >= $0.start && now < $0.end },
            next: statusEvents.first { $0.start > now }
        )
    }

    /// WidgetKit이 앱 종료 뒤에도 상태·거친 남은 시간 경계에서 다시 그릴 timeline 날짜.
    func glanceTimelineDates(from now: Date, limit: Int = 64) -> [Date] {
        let boundaries = flatMap { [$0.start, $0.end] }.filter { $0 > now }.sorted()
        var dates = [now]
        var cursor = now

        while dates.count < Swift.max(1, limit) {
            let status = glanceStatus(at: cursor)
            let target = status.current?.end ?? status.next?.start
            let labelChange = target.flatMap { nextRemainingRefresh(to: $0, after: cursor) }
            let eventChange = boundaries.first { $0 > cursor }
            guard let next = [labelChange, eventChange].compactMap({ $0 }).min() else { break }
            dates.append(next)
            cursor = next
        }
        return dates
    }
}

/// WidgetKit budget에 맞춘 거친 갱신: 65분 이하는 5분, 그보다 길면 1시간 간격.
private func nextRemainingRefresh(to target: Date, after now: Date) -> Date? {
    let seconds = target.timeIntervalSince(now)
    guard seconds > 0 else { return nil }
    let interval = seconds > 3_900 ? 3_600.0 : 300.0
    return min(target, now.addingTimeInterval(interval))
}

#if os(iOS)
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
        /// cap된 표시 segment와 별개인 현재/다음 판정용 compact 일정.
        var statusSegments: [GlanceEventSnapshot]?

        /// 지금 진행 중인 일정(없으면 nil).
        var currentTitle: String?
        var currentEnd: Date?
        /// 다음 일정(없으면 nil).
        var nextTitle: String?
        var nextStart: Date?
        /// 앱 언어가 영어인지(위젯이 App Group 없이도 앱 설정 따라 한/영 표시).
        var isEnglish: Bool = false
    }

    /// 예: "6월 17일 화요일"
    var dayLabel: String
}

extension ScheduleActivityAttributes.ContentState {
    func glanceStatus(at now: Date) -> GlanceStatus {
        guard let statusSegments, !statusSegments.isEmpty else { return segments.glanceStatus(at: now) }
        return statusSegments.glanceStatus(at: now)
    }
}
#endif

/// 일정들을 빈틈없이 붙여 바를 채우는 레이아웃 + 진행 위치 계산.
/// (앱·위젯 공통) 시간이 겹치는 일정들은 **한 세그먼트로 병합**한다 — eventIndices가 2개 이상이면
/// 겹침 칸(줄무늬로 표시). 진행 중이면 그 칸 안 비율, 쉬는 시간엔 다음 칸 경계에 정지.
struct PackedLayout {
    /// packed 한 칸 = 시간이 겹치는 일정들의 병합 구간. eventIndices 개수가 2 이상이면 겹침.
    /// start/end는 칸의 시각 범위 — 칸 안에서 각 일정을 실제 시각 비율로 배치(스테인글라스 겹침)하는 데 쓴다.
    struct Segment { let left: Double; let width: Double; let start: Date; let end: Date; let eventIndices: [Int] }

    let segments: [Segment]
    private let clusters: [(start: Date, end: Date)]

    init(intervals: [(start: Date, end: Date)], minWidth: Double = 0.05) {
        guard !intervals.isEmpty else { segments = []; clusters = []; return }

        // 1) 시작순 정렬(원 인덱스 보존) → 2) 시간이 겹치면(전이적) 한 클러스터로 병합
        let order = intervals.indices.sorted {
            intervals[$0].start != intervals[$1].start
                ? intervals[$0].start < intervals[$1].start
                : intervals[$0].end < intervals[$1].end
        }
        var built: [(start: Date, end: Date, idxs: [Int])] = []
        for oi in order {
            let iv = intervals[oi]
            if var last = built.last, iv.start < last.end {          // 겹침 → 병합
                last.end = max(last.end, iv.end); last.idxs.append(oi)
                built[built.count - 1] = last
            } else {
                built.append((iv.start, iv.end, [oi]))
            }
        }
        clusters = built.map { ($0.start, $0.end) }

        // 3) 클러스터 union 길이 비례 폭으로 빈틈없이 packed
        let durations = built.map { max(1, $0.end.timeIntervalSince($0.start)) }
        let total = durations.reduce(0, +)
        var widths = durations.map { max($0 / total, minWidth) }
        let sum = widths.reduce(0, +)
        widths = widths.map { $0 / sum }

        var acc = 0.0
        var segs: [Segment] = []
        for (k, c) in built.enumerated() {
            segs.append(Segment(left: acc, width: widths[k], start: c.start, end: c.end, eventIndices: c.idxs))
            acc += widths[k]
        }
        segments = segs
    }

    /// 진행 위치(0...1). 쉬는 시간엔 다음 칸 경계에 정지.
    func fraction(at now: Date) -> Double {
        guard !clusters.isEmpty else { return 0 }
        if now < clusters[0].start { return 0 }
        for i in clusters.indices {
            let c = clusters[i]
            if now < c.start { return segments[i].left }     // 쉬는 시간 → 경계 정지
            if now < c.end {
                let f = now.timeIntervalSince(c.start) / c.end.timeIntervalSince(c.start)
                return segments[i].left + segments[i].width * f  // 진행 중
            }
        }
        return 1
    }

    /// 지금이 쉬는 시간(어떤 일정에도 안 속하고 다음 일정이 남음)인지.
    func isWaiting(at now: Date) -> Bool {
        guard let first = clusters.first, let last = clusters.last else { return false }
        if now < first.start || now >= last.end { return false }
        return !clusters.contains { now >= $0.start && now < $0.end }
    }
}

// MARK: - 홈 화면 위젯 (App Group 공유)

/// 홈 위젯이 읽는 오늘(또는 다가오는) 하루 스냅샷. ContentState와 같은 정보지만 ActivityKit 비의존이라
/// 어느 타깃에서든 인코딩/디코딩된다.
struct HomeSnapshot: Codable {
    var dayLabel: String
    var dayStart: Date
    var dayEnd: Date
    var segments: [EventSnapshot]
    var currentTitle: String?
    var currentEnd: Date?
    var nextTitle: String?
    var nextStart: Date?
    var isEnglish: Bool = false
    var updatedAt: Date = .init()
}

/// DayPlan의 30분 앞 패딩을 되돌려 스냅샷이 대표하는 날짜를 복원한다.
func snapshotDay(from dayStart: Date, calendar: Calendar = .current) -> Date {
    let unpadded = calendar.date(byAdding: .minute, value: 30, to: dayStart) ?? dayStart
    return calendar.startOfDay(for: unpadded)
}

/// 과거 날짜 캐시가 현재 일정처럼 보이지 않게 한다. 미래 일정 폴백은 유지한다.
func snapshotIsDisplayable(dayStart: Date, at now: Date, calendar: Calendar = .current) -> Bool {
    snapshotDay(from: dayStart, calendar: calendar) >= calendar.startOfDay(for: now)
}

extension HomeSnapshot {
    func isDisplayable(at now: Date, calendar: Calendar = .current) -> Bool {
        snapshotIsDisplayable(dayStart: dayStart, at: now, calendar: calendar)
    }

    /// 마지막 일정 뒤에도 자정에 다시 그려 과거 스냅샷을 확실히 만료한다.
    func timelineDates(from now: Date, limit: Int = 64, calendar: Calendar = .current) -> [Date] {
        guard limit > 0 else { return [] }
        var dates = segments.glanceTimelineDates(from: now, limit: max(1, limit - 1))
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            dates.append(tomorrow)
        }
        return Array(Set(dates).sorted().prefix(limit))
    }
}

/// 앱↔위젯 공유 저장소(App Group). 앱이 오늘 스냅샷을 쓰고 홈 위젯이 읽는다.
enum SharedStore {
    static let appGroup = AppConfig.appGroupID
    private static let todayKey = "homeSnapshot.v1"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func writeToday(_ snapshot: HomeSnapshot) {
        guard let d = defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        d.set(data, forKey: todayKey)
    }

    static func readToday() -> HomeSnapshot? {
        guard let d = defaults, let data = d.data(forKey: todayKey) else { return nil }
        return try? JSONDecoder().decode(HomeSnapshot.self, from: data)
    }
}
