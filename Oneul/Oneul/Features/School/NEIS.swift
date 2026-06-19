import Foundation
import SwiftData

// MARK: - 설정 (앱 1개당 키 1개. 사용자는 입력 안 함)

enum NEISConfig {
    /// NEIS 인증키. open.neis.go.kr 에서 무료 발급 후 여기에 한 줄 넣으세요.
    /// 비어 있으면 학교 검색 시 안내가 뜹니다. (읽기 전용 공개데이터)
    static let apiKey = ""
}

// MARK: - 모델

struct School: Identifiable, Hashable {
    let office: String   // ATPT_OFCDC_SC_CODE (시도교육청)
    let code: String     // SD_SCHUL_CODE (학교코드)
    let name: String     // SCHUL_NM
    let kind: String     // SCHUL_KND_SC_NM (초/중/고)
    let address: String  // ORG_RDNMA
    var id: String { office + "-" + code }
}

struct TimetableEntry {
    let date: String     // yyyyMMdd
    let period: Int
    let subject: String
}

struct Meal: Identifiable {
    let type: String     // 조식/중식/석식
    let menu: String
    var id: String { type }
}

enum NEISError: LocalizedError {
    case noKey, noData, message(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "NEIS 키가 아직 설정되지 않았어요. (앱에 키 1개만 넣으면 됩니다)"
        case .noData: return "해당 정보를 찾지 못했어요."
        case .message(let m): return m
        }
    }
}

// MARK: - 표준 교시 시간 (고등학교 기준, 50분 수업)

enum PeriodTimes {
    /// 교시 → (시작시, 시작분, 종료시, 종료분)
    static let high: [Int: (Int, Int, Int, Int)] = [
        1: (8, 40, 9, 30), 2: (9, 40, 10, 30), 3: (10, 40, 11, 30), 4: (11, 40, 12, 30),
        5: (13, 30, 14, 20), 6: (14, 30, 15, 20), 7: (15, 30, 16, 20), 8: (16, 30, 17, 20)
    ]
}

// MARK: - 클라이언트

struct NEISClient {
    static let shared = NEISClient()
    private let base = "https://open.neis.go.kr/hub/"

    func searchSchools(_ name: String) async throws -> [School] {
        let rows = try await fetch("schoolInfo", [
            "SCHUL_NM": name, "pSize": "50"
        ], service: "schoolInfo")
        return rows.map {
            School(office: str($0["ATPT_OFCDC_SC_CODE"]), code: str($0["SD_SCHUL_CODE"]),
                   name: str($0["SCHUL_NM"]), kind: str($0["SCHUL_KND_SC_NM"]),
                   address: str($0["ORG_RDNMA"]))
        }
    }

    func fetchTimetable(school: School, grade: Int, classNm: String,
                        from: Date, to: Date) async throws -> [TimetableEntry] {
        let service = timetableService(kind: school.kind)
        let rows = try await fetch(service, [
            "ATPT_OFCDC_SC_CODE": school.office, "SD_SCHUL_CODE": school.code,
            "GRADE": String(grade), "CLASS_NM": classNm,
            "TI_FROM_YMD": ymd(from), "TI_TO_YMD": ymd(to), "pSize": "300"
        ], service: service)
        return rows.compactMap {
            guard let p = Int(str($0["PERIO"])) else { return nil }
            return TimetableEntry(date: str($0["ALL_TI_YMD"]), period: p, subject: str($0["ITRT_CNTNT"]))
        }
    }

    func fetchMeal(school: School, date: Date) async throws -> [Meal] {
        let rows = try await fetch("mealServiceDietInfo", [
            "ATPT_OFCDC_SC_CODE": school.office, "SD_SCHUL_CODE": school.code,
            "MLSV_YMD": ymd(date)
        ], service: "mealServiceDietInfo")
        return rows.map {
            Meal(type: str($0["MMEAL_SC_NM"]),
                 menu: str($0["DDISH_NM"]).replacingOccurrences(of: "<br/>", with: "\n"))
        }
    }

    // MARK: 내부

    private func timetableService(kind: String) -> String {
        if kind.contains("고") { return "hisTimetable" }
        if kind.contains("중") { return "misTimetable" }
        return "elsTimetable"
    }

    private func fetch(_ endpoint: String, _ params: [String: String],
                       service: String) async throws -> [[String: Any]] {
        guard !NEISConfig.apiKey.isEmpty else { throw NEISError.noKey }
        var comp = URLComponents(string: base + endpoint)!
        var items = [URLQueryItem(name: "KEY", value: NEISConfig.apiKey),
                     URLQueryItem(name: "Type", value: "json")]
        for (k, v) in params { items.append(URLQueryItem(name: k, value: v)) }
        comp.queryItems = items
        let (data, _) = try await URLSession.shared.data(from: comp.url!)
        return try Self.rows(from: data, service: service)
    }

    private static func rows(from data: Data, service: String) throws -> [[String: Any]] {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let result = obj?["RESULT"] as? [String: Any] {
            let msg = result["MESSAGE"] as? String ?? "오류"
            if (result["CODE"] as? String)?.contains("200") == true { return [] } // 데이터 없음
            throw NEISError.message(msg)
        }
        guard let arr = obj?[service] as? [[String: Any]] else { throw NEISError.noData }
        for part in arr {
            if let rows = part["row"] as? [[String: Any]] { return rows }
        }
        return []
    }

    private func str(_ v: Any?) -> String { (v as? String) ?? "" }
    private func ymd(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "ko_KR")
        return f.string(from: d)
    }
}

// MARK: - 시간표 → 반복 일정 변환

enum TimetableImporter {
    /// 이번 주 시간표를 읽어 요일별 수업을 **졸업(학년도 말)까지** 매주 반복으로 생성. 생성한 일정 수 반환.
    /// @MainActor: SwiftData 메인 컨텍스트 insert가 메인 스레드에서 일어나도록 (백그라운드 insert 크래시 방지).
    @MainActor
    static func importThisWeek(school: School, grade: Int, classNm: String,
                               into context: ModelContext) async throws -> Int {
        let cal = Calendar.current
        let todayMid = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: todayMid)          // 1=일 … 7=토
        let daysFromMon = (weekday + 5) % 7                            // 월=0
        guard let mon = cal.date(byAdding: .day, value: -daysFromMon, to: todayMid),
              let fri = cal.date(byAdding: .day, value: 4, to: mon) else { return 0 }

        let entries = try await NEISClient.shared.fetchTimetable(
            school: school, grade: grade, classNm: classNm, from: mon, to: fri)

        let until = graduationDate(kind: school.kind, grade: grade)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "ko_KR")
        var count = 0
        for e in entries {
            guard !e.subject.isEmpty,
                  let date = f.date(from: e.date),
                  let t = PeriodTimes.high[e.period],
                  let start = cal.date(bySettingHour: t.0, minute: t.1, second: 0, of: date),
                  let end = cal.date(bySettingHour: t.2, minute: t.3, second: 0, of: date) else { continue }
            let wd = cal.component(.weekday, from: date)
            EventActions.create(title: e.subject, start: start, end: end, location: "",
                                reminderMinutes: -1, recurrence: .weekly,
                                weekdays: [wd], endDate: until, into: context)
            count += 1
        }
        return count
    }

    /// 졸업일(학년도 말 = 2월 말일). 초=6년, 중/고/특=3년.
    static func graduationDate(kind: String, grade: Int) -> Date {
        let cal = Calendar.current
        let total = kind.contains("초") ? 6 : 3
        let now = Date()
        let month = cal.component(.month, from: now)
        let year = cal.component(.year, from: now)
        let currentSchoolYearEnd = (month >= 3) ? year + 1 : year   // 학년도는 3월 시작, 2월 말 종료
        let gradYear = currentSchoolYearEnd + max(0, total - grade)
        let mar1 = cal.date(from: DateComponents(year: gradYear, month: 3, day: 1)) ?? now
        return cal.date(byAdding: .day, value: -1, to: mar1) ?? mar1   // 2월 말일
    }
}
