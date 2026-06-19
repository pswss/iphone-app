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
    let calorie: String  // CAL_INFO
    var id: String { type }
}

struct AcademicEvent {
    let date: String          // yyyyMMdd (AA_YMD)
    let name: String          // EVENT_NM
    let kind: String          // SBTR_DD_SC_NM (수업일/휴업일 등)
    let gradeFlags: [String]  // [1학년, 2학년, 3학년] 적용 YN ("Y"/"N"/"")

    /// 해당 학년에 적용되는 일정인지 — 그 학년 플래그가 명시적으로 "N"이면 제외(예: 고2한테 대수능모의평가),
    /// 그 외(Y/빈값/학년정보 없음)는 포함.
    func applies(toGrade g: Int) -> Bool {
        guard g >= 1, g <= gradeFlags.count else { return true }
        return gradeFlags[g - 1] != "N"
    }
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

enum PeriodSchedule {
    static let count = 7

    /// 보평고 기본값 (시작분, 종료분 — 자정 기준 분).
    static let defaults: [(Int, Int)] = [
        (9 * 60 + 10, 10 * 60 + 0),   // 1교시 09:10~10:00
        (10 * 60 + 10, 11 * 60 + 0),  // 2교시 10:10~11:00
        (11 * 60 + 10, 12 * 60 + 0),  // 3교시 11:10~12:00
        (13 * 60 + 0, 13 * 60 + 50),  // 4교시 13:00~13:50 (점심 12:00~13:00)
        (14 * 60 + 0, 14 * 60 + 50),  // 5교시 14:00~14:50
        (15 * 60 + 0, 15 * 60 + 50),  // 6교시 15:00~15:50
        (16 * 60 + 0, 16 * 60 + 50)   // 7교시 16:00~16:50
    ]

    static func startMinutes(_ p: Int) -> Int {
        UserDefaults.standard.object(forKey: "bell.\(p).start") as? Int ?? defaults[p - 1].0
    }
    static func endMinutes(_ p: Int) -> Int {
        UserDefaults.standard.object(forKey: "bell.\(p).end") as? Int ?? defaults[p - 1].1
    }
    static func setStart(_ p: Int, _ minutes: Int) { UserDefaults.standard.set(minutes, forKey: "bell.\(p).start") }
    static func setEnd(_ p: Int, _ minutes: Int) { UserDefaults.standard.set(minutes, forKey: "bell.\(p).end") }

    /// 교시 → (시작시, 시작분, 종료시, 종료분).
    static func time(period p: Int) -> (Int, Int, Int, Int)? {
        guard p >= 1, p <= count else { return nil }
        let s = startMinutes(p), e = endMinutes(p)
        return (s / 60, s % 60, e / 60, e % 60)
    }
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
                 menu: str($0["DDISH_NM"]).replacingOccurrences(of: "<br/>", with: "\n"),
                 calorie: str($0["CAL_INFO"]))
        }
    }

    /// 학급 정보 → 그 학교·학년의 실제 반 목록(숫자 오름차순).
    func fetchClasses(school: School, grade: Int) async throws -> [String] {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let ay = cal.component(.month, from: Date()) >= 3 ? year : year - 1   // 학년도
        let rows = try await fetch("classInfo", [
            "ATPT_OFCDC_SC_CODE": school.office, "SD_SCHUL_CODE": school.code,
            "AY": String(ay), "GRADE": String(grade), "pSize": "100"
        ], service: "classInfo")
        let names = rows.compactMap { ($0["CLASS_NM"] as? String) }.filter { !$0.isEmpty }
        return Array(Set(names)).sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    /// 학사일정(시험·행사 등).
    func fetchSchedule(school: School, from: Date, to: Date) async throws -> [AcademicEvent] {
        let rows = try await fetch("SchoolSchedule", [
            "ATPT_OFCDC_SC_CODE": school.office, "SD_SCHUL_CODE": school.code,
            "AA_FROM_YMD": ymd(from), "AA_TO_YMD": ymd(to), "pSize": "500"
        ], service: "SchoolSchedule")
        return rows.compactMap {
            let name = str($0["EVENT_NM"])
            guard !name.isEmpty else { return nil }
            return AcademicEvent(date: str($0["AA_YMD"]), name: name, kind: str($0["SBTR_DD_SC_NM"]),
                                 gradeFlags: [str($0["ONE_GRADE_EVENT_YN"]),
                                              str($0["TW_GRADE_EVENT_YN"]),
                                              str($0["THREE_GRADE_EVENT_YN"])])
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
    /// 시간표 + 학사일정 전부 가져오기. 재가져오기 시 이전 학교 일정(timetable/academic)을 먼저 삭제.
    @MainActor
    static func importAll(school: School, grade: Int, classNm: String,
                          into context: ModelContext) async throws -> (timetable: Int, academic: Int) {
        EventActions.deleteBySource("timetable", in: context)
        EventActions.deleteBySource("academic", in: context)

        let cal = Calendar.current
        let until = graduationDate(kind: school.kind, grade: grade)

        // 학사일정 먼저 — 시험일을 시간표에서 제외하려고
        let academic = (try? await NEISClient.shared.fetchSchedule(
            school: school, from: cal.startOfDay(for: Date()), to: until)) ?? []
        let ac = createAcademic(academic, into: context)
        let examDays = examDateSet(academic)

        let tt = try await importTimetable(school: school, grade: grade, classNm: classNm,
                                           until: until, excludeDays: examDays, into: context)
        return (tt, ac)
    }

    /// 사용자가 고른 (요일·교시·과목)으로 시간표 생성 (선택과목 반영).
    /// 시험·방학날은 수업 제외, 시간표는 **다음 방학(학기 끝) 전까지만** 생성.
    @MainActor
    static func importSelections(school: School, grade: Int,
                                 selections: [(weekday: Int, period: Int, subject: String)],
                                 into context: ModelContext) async throws -> (timetable: Int, academic: Int) {
        EventActions.deleteBySource("timetable", in: context)
        EventActions.deleteBySource("academic", in: context)

        let cal = Calendar.current
        let gradEnd = graduationDate(kind: school.kind, grade: grade)
        // 학년에 맞는 일정만 (예: 고2한테 대수능모의평가·고3 전용 학평 제외)
        let academic = ((try? await NEISClient.shared.fetchSchedule(
            school: school, from: cal.startOfDay(for: Date()), to: gradEnd)) ?? [])
            .filter { $0.applies(toGrade: grade) }
        let (vacationDays, semesterEnd, ac) = processAcademic(academic, into: context)
        let until = semesterEnd ?? gradEnd   // 방학 전까지만 (없으면 졸업까지)
        // 공휴일도 수업 제외
        var holidays: Set<Date> = []
        var hd = cal.startOfDay(for: Date())
        while hd <= until {
            if Holidays.name(for: hd) != nil { holidays.insert(hd) }
            guard let nx = cal.date(byAdding: .day, value: 1, to: hd) else { break }
            hd = nx
        }
        let excludeDays = examDateSet(academic).union(vacationDays).union(holidays)

        let todayMid = cal.startOfDay(for: Date())
        let daysFromMon = (cal.component(.weekday, from: todayMid) + 5) % 7
        guard let mon = cal.date(byAdding: .day, value: -daysFromMon, to: todayMid) else { return (0, ac) }

        var count = 0
        for sel in selections where !sel.subject.isEmpty {
            guard let t = PeriodSchedule.time(period: sel.period) else { continue }
            let offset = (sel.weekday + 5) % 7   // 월(2)=0 … 금(6)=4
            guard let date = cal.date(byAdding: .day, value: offset, to: mon),
                  let start = cal.date(bySettingHour: t.0, minute: t.1, second: 0, of: date),
                  let end = cal.date(bySettingHour: t.2, minute: t.3, second: 0, of: date) else { continue }
            EventActions.create(title: sel.subject, start: start, end: end, location: "",
                                reminderMinutes: -1, recurrence: .weekly, weekdays: [sel.weekday],
                                endDate: until, source: "timetable", excludeDays: excludeDays, into: context)
            count += 1
        }
        return (count, ac)
    }

    /// 학사일정 처리: 방학은 멀티데이 1개로, 시험·행사는 단일일로 생성.
    /// 반환: (방학날 집합, 다음 학기 끝=방학 직전 날, 생성 수)
    @MainActor
    private static func processAcademic(_ events: [AcademicEvent], into context: ModelContext) -> (Set<Date>, Date?, Int) {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "ko_KR")
        var vacationDays: Set<Date> = []
        var vacByName: [String: [Date]] = [:]
        var others: [(day: Date, name: String, isExam: Bool)] = []
        for e in events {
            guard let day = f.date(from: e.date) else { continue }
            if e.name.contains("방학") && !e.name.contains("방학식") {
                vacationDays.insert(cal.startOfDay(for: day))
                vacByName[e.name, default: []].append(cal.startOfDay(for: day))
            } else if isWanted(e) {
                others.append((day, e.name, examWords.contains(where: e.name.contains)))
            }
        }
        var count = 0
        // 방학 → 멀티데이 한 개
        for (name, dates) in vacByName {
            let s = dates.sorted()
            guard let first = s.first, let last = s.last,
                  let end = cal.date(bySettingHour: 23, minute: 59, second: 0, of: last) else { continue }
            context.insert(ScheduleEvent(title: name, start: cal.startOfDay(for: first), end: end,
                                         location: "", reminderMinutes: -1, source: "academic"))
            count += 1
        }
        // 시험·행사 → 단일일
        for o in others {
            guard let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: o.day),
                  let end = cal.date(bySettingHour: o.isExam ? 12 : 10, minute: 0, second: 0, of: o.day) else { continue }
            EventActions.create(title: o.name, start: start, end: end, location: "",
                                reminderMinutes: -1, recurrence: .none, source: "academic", into: context)
            count += 1
        }
        try? context.save()
        // 다음 방학 시작 직전 = 이번 학기 끝
        let today0 = cal.startOfDay(for: Date())
        let vacStarts = vacByName.values.compactMap { $0.sorted().first }.filter { $0 > today0 }.sorted()
        let semesterEnd = vacStarts.first.flatMap { cal.date(byAdding: .day, value: -1, to: $0) }
        return (vacationDays, semesterEnd, count)
    }

    /// 시험일(`excludeDays`)엔 평소 수업을 넣지 않음.
    @MainActor
    private static func importTimetable(school: School, grade: Int, classNm: String,
                                        until: Date, excludeDays: Set<Date>,
                                        into context: ModelContext) async throws -> Int {
        let cal = Calendar.current
        let todayMid = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: todayMid)          // 1=일 … 7=토
        let daysFromMon = (weekday + 5) % 7                            // 월=0
        guard let mon = cal.date(byAdding: .day, value: -daysFromMon, to: todayMid),
              let fri = cal.date(byAdding: .day, value: 4, to: mon) else { return 0 }

        let entries = try await NEISClient.shared.fetchTimetable(
            school: school, grade: grade, classNm: classNm, from: mon, to: fri)

        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "ko_KR")
        var count = 0
        for e in entries {
            guard !e.subject.isEmpty,
                  let date = f.date(from: e.date),
                  let t = PeriodSchedule.time(period: e.period),
                  let start = cal.date(bySettingHour: t.0, minute: t.1, second: 0, of: date),
                  let end = cal.date(bySettingHour: t.2, minute: t.3, second: 0, of: date) else { continue }
            let wd = cal.component(.weekday, from: date)
            EventActions.create(title: e.subject, start: start, end: end, location: "",
                                reminderMinutes: -1, recurrence: .weekly,
                                weekdays: [wd], endDate: until, source: "timetable",
                                excludeDays: excludeDays, into: context)
            count += 1
        }
        return count
    }

    /// 학사일정에서 시험 + 주요 행사만 일정으로 생성 (토요휴업일 등 잡다 제외).
    @MainActor
    private static func createAcademic(_ events: [AcademicEvent], into context: ModelContext) -> Int {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "ko_KR")
        var count = 0
        for e in events where isWanted(e) {
            guard let day = f.date(from: e.date),
                  let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) else { continue }
            let exam = examWords.contains(where: e.name.contains)
            let end = cal.date(bySettingHour: exam ? 12 : 10, minute: 0, second: 0, of: day)
                ?? start.addingTimeInterval(3600)
            EventActions.create(title: e.name, start: start, end: end, location: "",
                                reminderMinutes: -1, recurrence: .none, source: "academic", into: context)
            count += 1
        }
        return count
    }

    /// 실제 시험일(수업 제외 대상) 집합.
    private static func examDateSet(_ events: [AcademicEvent]) -> Set<Date> {
        let cal = Calendar.current
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "ko_KR")
        var set: Set<Date> = []
        for e in events where examDayWords.contains(where: e.name.contains) {
            if let d = f.date(from: e.date) { set.insert(cal.startOfDay(for: d)) }
        }
        return set
    }

    private static let examWords = ["고사", "시험", "평가", "모의", "수능", "학력"]
    /// 수업을 빼야 하는 진짜 시험일(수행평가·봉사평가 등은 제외).
    private static let examDayWords = ["고사", "시험", "모의", "수능", "학력평가"]
    private static let majorWords = ["방학", "개학", "입학식", "졸업식", "시업식", "축제",
                                     "체육대회", "수련회", "수학여행", "현장체험", "재량휴업",
                                     "대체공휴일", "개교기념일", "소풍", "발표회"]
    private static func isWanted(_ e: AcademicEvent) -> Bool {
        if e.name.contains("토요휴업일") { return false }
        return examWords.contains(where: e.name.contains) || majorWords.contains(where: e.name.contains)
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

    // MARK: - 선택과목 분석/배치 (대화형 화면 + 자동 갱신 공용)

    struct GradeTimetable {
        var electiveSet: Set<String> = []
        var electives: [String] = []
        var classTT: [(weekday: Int, period: Int, subject: String)] = []
        var offered: [String: Set<String>] = [:]   // "wd-p" → 그 교시 선택과목 후보
    }

    /// 학년 전체 반 조회 → "일부 반만 듣는 과목 = 선택과목" 판별 + 본인 반 시간표 + 교시별 선택지.
    static func analyzeGrade(school: School, grade: Int, classNm: String) async -> GradeTimetable {
        let classes = (try? await NEISClient.shared.fetchClasses(school: school, grade: grade)) ?? []
        let useClasses = classes.isEmpty ? [classNm] : classes
        let cal = Calendar.current
        let todayMid = cal.startOfDay(for: Date())
        let daysFromMon = (cal.component(.weekday, from: todayMid) + 5) % 7
        guard let mon = cal.date(byAdding: .day, value: -daysFromMon, to: todayMid),
              let fri = cal.date(byAdding: .day, value: 4, to: mon) else { return GradeTimetable() }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; f.locale = Locale(identifier: "ko_KR")

        var classOf: [String: Set<String>] = [:]   // 과목 → 듣는 반
        var slotSubs: [String: Set<String>] = [:]  // "wd-p" → 과목들
        var mine: [String: String] = [:]           // "wd-p" → 본인 반 과목
        await withTaskGroup(of: (String, [TimetableEntry]).self) { group in
            for c in useClasses {
                group.addTask {
                    let e = (try? await NEISClient.shared.fetchTimetable(
                        school: school, grade: grade, classNm: c, from: mon, to: fri)) ?? []
                    return (c, e)
                }
            }
            for await (c, entries) in group {
                for e in entries where !e.subject.isEmpty {
                    guard let date = f.date(from: e.date) else { continue }
                    let s = e.subject.replacingOccurrences(of: "[보강]", with: "")
                    let key = "\(cal.component(.weekday, from: date))-\(e.period)"
                    classOf[s, default: []].insert(c)
                    slotSubs[key, default: []].insert(s)
                    if c == classNm { mine[key] = s }
                }
            }
        }

        let threshold = max(2, useClasses.count - 1)   // 이 수 이상 들으면 공통과목
        func isActivity(_ s: String) -> Bool {
            ["자율", "동아리", "진로", "봉사", "자치", "창의적", "체험"].contains { s.contains($0) }
        }
        let electiveSet = Set(classOf.keys.filter { !isActivity($0) && (classOf[$0]?.count ?? 0) < threshold })
        var offered: [String: Set<String>] = [:]
        for (key, subs) in slotSubs {
            let e = subs.filter { electiveSet.contains($0) }
            if !e.isEmpty { offered[key] = e }
        }
        let classTT: [(weekday: Int, period: Int, subject: String)] = mine.compactMap { (key, s) in
            let p = key.split(separator: "-")
            guard p.count == 2, let wd = Int(p[0]), let per = Int(p[1]) else { return nil }
            return (wd, per, s)
        }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        return GradeTimetable(electiveSet: electiveSet, electives: electiveSet.sorted(),
                              classTT: classTT, offered: offered)
    }

    /// 체크한 선택과목 → (요일,교시,과목) 선택 목록. 공통/창체는 본인 반 그대로.
    static func resolveSelections(_ g: GradeTimetable, checked: Set<String>) -> [(weekday: Int, period: Int, subject: String)] {
        var out: [(weekday: Int, period: Int, subject: String)] = []
        for slot in g.classTT {
            if g.electiveSet.contains(slot.subject) {
                let opts = g.offered["\(slot.weekday)-\(slot.period)"] ?? []
                let mineHere = opts.intersection(checked)
                if mineHere.contains(slot.subject) {
                    out.append((slot.weekday, slot.period, slot.subject))
                } else if let chosen = mineHere.first {
                    out.append((slot.weekday, slot.period, chosen))
                }
                // 체크 없으면 공강 → 건너뜀
            } else {
                out.append((slot.weekday, slot.period, slot.subject))
            }
        }
        return out
    }
}

// MARK: - 시간표 설정 저장 + 일일 자동 갱신

/// 자동 갱신용 시간표 설정 (학교는 neis* @AppStorage 재사용).
enum TimetableSetup {
    static func save(grade: Int, classNm: String, electives: Set<String>) {
        let d = UserDefaults.standard
        d.set(grade, forKey: "ttGrade")
        d.set(classNm, forKey: "ttClass")
        d.set(Array(electives), forKey: "ttElectives")
        d.set(true, forKey: "ttSetup")
    }
    static func load() -> (grade: Int, classNm: String, electives: Set<String>)? {
        let d = UserDefaults.standard
        guard d.bool(forKey: "ttSetup") else { return nil }
        let grade = d.integer(forKey: "ttGrade")
        let classNm = d.string(forKey: "ttClass") ?? ""
        guard grade > 0, !classNm.isEmpty else { return nil }
        let electives = Set((d.array(forKey: "ttElectives") as? [String]) ?? [])
        return (grade, classNm, electives)
    }
}

/// 하루 1회: 학사일정 + (설정 있으면) 시간표를 다시 가져와 갱신. 2학기·새 일정 자동 반영.
enum SchoolAutoRefresh {
    @MainActor
    static func runIfDue(context: ModelContext) async {
        let d = UserDefaults.standard
        if let last = d.object(forKey: "lastSchoolRefresh") as? Date,
           Date().timeIntervalSince(last) < 23 * 3600 { return }
        guard let setup = TimetableSetup.load(), let school = currentSchool() else { return }
        let g = await TimetableImporter.analyzeGrade(school: school, grade: setup.grade, classNm: setup.classNm)
        guard !g.classTT.isEmpty else { return }   // 네트워크 실패 시 기존 유지(덮어쓰지 않음)
        let sels = TimetableImporter.resolveSelections(g, checked: setup.electives)
        if (try? await TimetableImporter.importSelections(
            school: school, grade: setup.grade, selections: sels, into: context)) != nil {
            d.set(Date(), forKey: "lastSchoolRefresh")
        }
    }

    private static func currentSchool() -> School? {
        let d = UserDefaults.standard
        let code = d.string(forKey: "neisCode") ?? ""
        guard !code.isEmpty else { return nil }
        return School(office: d.string(forKey: "neisOffice") ?? "", code: code,
                      name: d.string(forKey: "neisName") ?? "",
                      kind: d.string(forKey: "neisKind") ?? "", address: "")
    }
}
