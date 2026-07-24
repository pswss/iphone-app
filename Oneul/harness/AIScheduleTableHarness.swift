// xcrun swiftc -parse-as-library harness/AIScheduleTableHarness.swift Oneul/Features/AI/AICommon.swift Oneul/Features/AI/AICommand.swift Oneul/Features/AI/FastScheduleParser.swift -o /private/tmp/oneul-ai-table-harness
// /private/tmp/oneul-ai-table-harness
import Foundation

enum Recurrence: String { case none, daily, weekly, biweekly, monthly, yearly }
enum Appearance: String { case system, light, dark }
final class AppLanguage {
    static let shared = AppLanguage()
    func tr(_ text: String) -> String { text }
}

@main
struct AIScheduleTableHarness {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()
    static let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 8))!

    static func main() {
        let weekly = """
        교시\t시간\t월요일\t화요일\t수요일\t목요일\t금요일
        1교시\t09:00–09:50\t국어\t수학\t-\t과학\t영어
        2교시\t10:00~10:50\t수학\t국어\t체육\t영어\t과학
        """
        let weeklyEvents = FastScheduleParser.parseEvents(text: weekly, now: now, cal: calendar)!
        assert(weeklyEvents.count == 9)
        assert(weeklyEvents.allSatisfy { $0.recurrence == .weekly && $0.weekdays.count == 1 })
        let mondayKorean = weeklyEvents.first { $0.title == "국어" && $0.weekdays == [2] }!
        assert(calendar.component(.hour, from: mondayKorean.start) == 9)
        assert(mondayKorean.end.timeIntervalSince(mondayKorean.start) == 50 * 60)

        let englishWeekly = """
        Period\tTime\tMonday\tTuesday
        1\t13:00–13:45\tPhysics\tChemistry
        """
        let englishEvents = FastScheduleParser.parseEvents(text: englishWeekly, now: now, cal: calendar)!
        assert(englishEvents.count == 2)
        assert(englishEvents.allSatisfy { $0.recurrence == .weekly && $0.end.timeIntervalSince($0.start) == 45 * 60 })

        let dated = """
        날짜\t시간\t내용\t장소
        2026.7.27.\t14:00~15:30\t프로젝트 회의\t서울 회의실
        7월 28일\t09:30\t치과\t강남 치과
        """
        let datedEvents = FastScheduleParser.parseEvents(text: dated, now: now, cal: calendar)!
        assert(datedEvents.count == 2)
        assert(datedEvents[0].title == "프로젝트 회의" && datedEvents[0].location == "서울 회의실")
        assert(calendar.component(.day, from: datedEvents[0].start) == 27)
        assert(datedEvents[1].title == "치과" && datedEvents[1].location == "강남 치과")

        let malformed = """
        교시\t시간\t월요일\t화요일
        1교시\t오전\t국어\t수학
        """
        assert(FastScheduleParser.parseEvents(text: malformed, now: now, cal: calendar) == nil)
        assert(FastScheduleParser.parseEvents(text: "품목\t수량\t단가\n사과\t3\t1000", now: now, cal: calendar) == nil)
        print("AIScheduleTableHarness PASS")
    }
}
