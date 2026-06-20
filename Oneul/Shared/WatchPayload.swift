import Foundation

/// 아이폰 → 애플워치로 보내는 오늘 일정 스냅샷(WatchConnectivity).
/// App Group이 필요 없어 무료 개발자 계정에서도 동작한다.
struct WatchSchedulePayload: Codable, Equatable {
    var dayLabel: String
    var dayStart: Date
    var dayEnd: Date
    var events: [EventSnapshot]
    var currentTitle: String?
    var currentEnd: Date?
    var nextTitle: String?
    var nextStart: Date?
    var updatedAt: Date

    static let empty = WatchSchedulePayload(
        dayLabel: "", dayStart: .now, dayEnd: .now, events: [],
        currentTitle: nil, currentEnd: nil, nextTitle: nil, nextStart: nil,
        updatedAt: .distantPast)
}
