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

        // Attached timetable shape, anonymized: weekday and weekend panels have separate time columns.
        var boxes = [PhotoTextBox(text: "주간 계획 [ 7/22 ~ 8/14 ]", x: 0.28, y: 0.78, width: 0.30, height: 0.03)]
        let weekdayColumns = [("월", 0.194), ("화", 0.292), ("수", 0.386), ("목", 0.483), ("금", 0.577)]
        let weekendColumns = [("토", 0.786), ("일", 0.885)]
        for (day, x) in weekdayColumns + weekendColumns {
            boxes.append(PhotoTextBox(text: day, x: x - 0.02, y: 0.57, width: 0.04, height: 0.03))
        }
        let rows = [0.519, 0.417, 0.313]
        for (time, y) in zip(["10:00 ~ 1:00", "2:00 ~ 5:00", "6:00 ~ 10:00"], rows) {
            boxes.append(PhotoTextBox(text: time, x: 0.063, y: y, width: 0.09, height: 0.03))
        }
        for (time, y) in zip(["9:00 ~ 12:00", "1:00 ~ 5:00", "6:00 ~ 9:00"], rows) {
            boxes.append(PhotoTextBox(text: time, x: 0.65, y: y, width: 0.09, height: 0.03))
        }
        for (column, (_, x)) in weekdayColumns.enumerated() {
            for (row, y) in rows.enumerated() {
                var title = "자습"
                if column == 1 && row == 1 { title = "확률과 통계" }
                if column == 2 && row == 2 { title = "BLACK 수일" }
                boxes.append(PhotoTextBox(text: title, x: x - 0.04, y: y, width: 0.08, height: 0.03))
            }
        }
        boxes += [
            PhotoTextBox(text: "확률과 통계", x: 0.746, y: rows[2], width: 0.08, height: 0.03),
            PhotoTextBox(text: "BLACK 수일", x: 0.845, y: rows[1], width: 0.08, height: 0.03),
            PhotoTextBox(text: "점심시간", x: 0.40, y: 0.463, width: 0.08, height: 0.03),
            PhotoTextBox(text: "저녁시간", x: 0.40, y: 0.360, width: 0.08, height: 0.03),
        ]
        let photoText = PhotoScheduleLayout.normalizedScheduleText(boxes: boxes, now: now, calendar: calendar)!
        let photoLines = photoText.components(separatedBy: .newlines)
        assert(photoLines.count == 60)
        assert(photoText.contains("7/28 14:00~17:00 확률과 통계"))
        assert(photoText.contains("7/22 18:00~22:00 BLACK 수일"))
        assert(photoText.contains("7/25 18:00~21:00 확률과 통계"))
        assert(photoText.contains("7/26 13:00~17:00 BLACK 수일"))
        assert(!photoText.contains("점심") && !photoText.contains("저녁"))
        let photoEvents = FastScheduleParser.parseEvents(text: photoText, now: now, cal: calendar)!
        assert(photoEvents.count == 60)
        assert(photoEvents.allSatisfy { $0.recurrence == .none && calendar.component(.year, from: $0.start) == 2026 })
        assert(photoEvents.contains { $0.title == "BLACK 수일" })
        assert(PhotoScheduleLayout.normalizedScheduleText(boxes: Array(boxes.prefix(8)), now: now,
                                                          calendar: calendar) == nil)
        let partialPanel = boxes.filter { !($0.x < 0.15 && $0.text.contains("~")) }
        assert(PhotoScheduleLayout.normalizedScheduleText(boxes: partialPanel, now: now, calendar: calendar) == nil)
        print("AIScheduleTableHarness PASS")
    }
}
