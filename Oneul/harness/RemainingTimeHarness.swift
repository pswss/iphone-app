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
        print("ALL PASS")
    }
}
