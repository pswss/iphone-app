// Run: bash harness/run_school_import.sh
import Foundation
import SwiftData

// No real credentials, network, or holiday lookup in these school-import fixtures.
enum Secrets {
    static let neisProxyBase = "https://oneul-school-test.invalid/"
    static let neisBakedKey = ""
}
enum Holidays { static func name(for day: Date) -> String? { nil } }

final class SchoolFixtureProtocol: URLProtocol {
    static var rows: [String: [[String: Any]]] = [:]
    static var failedService = ""
    static var failedClass = ""
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "oneul-school-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let service = url.lastPathComponent
        let classNm = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "CLASS_NM" }?.value
        if service == Self.failedService && (Self.failedClass.isEmpty || Self.failedClass == classNm) {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let data = try! JSONSerialization.data(withJSONObject: [service: [["row": Self.rows[service] ?? []]]])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                            headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct SchoolImportHarness {
    @MainActor
    static func main() async throws {
        let defaults = UserDefaults.standard
        let keys = ["ttGrade", "ttClass", "ttElectives", "ttCommonOverride", "ttPicks", "ttSchoolCode",
                    "ttSetup", "ttYear", "neisCode", "sourceTombstones"]
        let saved = keys.map { ($0, defaults.object(forKey: $0)) }
        defer { for (key, value) in saved { defaults.set(value, forKey: key) } }
        for key in keys { defaults.removeObject(forKey: key) }
        assert(URLProtocol.registerClass(SchoolFixtureProtocol.self))
        defer { URLProtocol.unregisterClass(SchoolFixtureProtocol.self) }

        for subject in ["융합과학탐구", "융합 과학 탐구", "윤리", "생활과 윤리", "윤리와 사상", "수능 영어"] {
            assert(NEISClient.cleanSubject(subject) == subject)
        }
        assert(NEISClient.cleanSubject("[보강] 1학기 2차 정기시험 윤리") == "윤리")
        assert(TimetableImporter.normalizeSubject(" 영어\u{00a0}Ⅰ\n") == TimetableImporter.normalizeSubject("영어 I"))
        assert(TimetableImporter.normalizeSubject("융합\n과학 탐구") == "융합과학탐구")
        assert(TimetableImporter.normalizeSubject("윤리") != TimetableImporter.normalizeSubject("윤리와 사상"))
        for marker in ["전국연합평가", "전국 연합 학력 평가(1,2학년)", "대수능모의평가", "여름방학", "-"] {
            assert(NEISClient.cleanSubject(marker).isEmpty, marker)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let monday = cal.date(byAdding: .day, value: -((cal.component(.weekday, from: today) + 5) % 7), to: today)!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        func date(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: monday)! }
        func entry(_ subject: String, _ period: Int, _ offset: Int = 0) -> TimetableEntry {
            TimetableEntry(date: formatter.string(from: date(offset)), period: period, subject: subject)
        }
        let data = [
            "1": [entry("융합과학탐구", 1), entry("융합 과학 탐구", 2), entry("영어Ⅰ", 3),
                  entry("전국연합평가", 1, 7)],
            "2": [entry("윤리", 1), entry("윤리", 2), entry("영어 I", 3)],
            "3": [entry("물리학", 1), entry("물리학", 2), entry("영어\u{00a0}I", 3), entry("지리", 1, -7)],
            "4": [entry("세계사", 1), entry("세계사", 2), entry("영어I", 3)]
        ]
        let analysis = TimetableImporter.analyzeGrade(data, classNm: "1")
        let electiveKeys = Set(analysis.electives.map(TimetableImporter.normalizeSubject))
        assert(electiveKeys.contains("융합과학탐구") && electiveKeys.contains("윤리"))
        assert(!electiveKeys.contains("영어I") && !electiveKeys.contains("전국연합평가"))
        assert(analysis.classTT.count == 3)
        assert(!(analysis.offered["2-1"] ?? []).contains("지리"))
        let singleClass = TimetableImporter.analyzeGrade(["1": data["1"]!], classNm: "1")
        assert(singleClass.electives.isEmpty && singleClass.classTT.count == 3)
        let override = TimetableImporter.analyzeGrade(data, classNm: "1", commonOverride: ["융합\n과학탐구"])
        assert(!override.electives.contains { TimetableImporter.normalizeSubject($0) == "융합과학탐구" })

        let picks = ["2-1": "윤리", "2-2": "융합과학탐구"]
        TimetableSetup.save(grade: 2, classNm: "1", electives: ["융합과학탐구", "윤리"], commonOverride: [], picks: picks)
        let setup = TimetableSetup.load()!
        assert(setup.picks == picks)
        let selected = TimetableImporter.resolveSelections(analysis, checked: setup.electives, picks: setup.picks)
        assert(selected[0].subject == "윤리")
        assert(TimetableImporter.normalizeSubject(selected[1].subject) == "융합과학탐구")
        assert(TimetableImporter.resolveSelections(analysis, checked: []).count == 1)
        let spacedEthics = TimetableImporter.resolveSelections(analysis, checked: ["윤\u{00a0}리"])
        assert(spacedEthics.filter { $0.subject == "윤리" }.count == 2)
        let blank = TimetableImporter.resolveSelections(analysis, checked: ["윤리"], picks: ["2-1": ""])
        assert(!blank.contains { $0.period == 1 } && blank.contains { $0.period == 2 && $0.subject == "윤리" })
        defaults.set("different-school", forKey: "neisCode")
        assert(TimetableSetup.load() == nil)
        defaults.removeObject(forKey: "neisCode")
        print("PASS: subject normalization, elective recognition, saved period assignments and empty slots")

        let school = School(office: "TEST", code: "TEST", name: "Fixture", kind: "고등학교", address: "")
        func academic(_ name: String, _ offset: Int, _ flags: [String]) -> [String: Any] {
            var row: [String: Any] = ["AA_YMD": formatter.string(from: date(offset)), "EVENT_NM": name]
            for (prefix, flag) in zip(["ONE", "TW", "THREE", "FR", "FIV", "SIX"], flags) {
                row["\(prefix)_GRADE_EVENT_YN"] = flag
            }
            return row
        }
        SchoolFixtureProtocol.rows = [
            "SchoolSchedule": [academic("전국연합평가", 8, ["Y", "Y", "N", "N", "N", "N"]),
                               academic("전국연합평가(3학년)", 9, ["N", " n ", "Y", "N", "N", "N"]),
                               academic("여름방학", 18, ["Y", "Y", "Y", "Y", "Y", "Y"])],
            "hisTimetable": data["1"]!.map { ["ALL_TI_YMD": $0.date, "PERIO": String($0.period), "ITRT_CNTNT": $0.subject] },
            "classInfo": [["CLASS_NM": "1"], ["CLASS_NM": "2"]]
        ]
        let schedule = try await NEISClient.shared.fetchSchedule(school: school, grade: 2, from: today, to: date(30))
        assert(schedule.count == 2 && schedule[0].date == formatter.string(from: date(8)))
        let sixthGrade = try await NEISClient.shared.fetchSchedule(school: school, grade: 6, from: today, to: date(30))
        assert(sixthGrade.map(\.name) == ["여름방학"])
        let container = try ModelContainer(for: ScheduleEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        for simpleImport in [true, false] {
            if simpleImport {
                _ = try await TimetableImporter.importAll(school: school, grade: 2, classNm: "1", into: context)
            } else {
                // Include a Tuesday class so the actual exam-day exclusion is exercised.
                _ = try await TimetableImporter.importSelections(school: school, grade: 2,
                                                                 selections: selected + [(3, 1, "윤리")], into: context)
            }
            let events = try context.fetch(FetchDescriptor<ScheduleEvent>())
            let exams = events.filter { $0.title.contains("전국연합") }
            assert(exams.count == 1 && exams[0].source == "academic" && exams[0].recurrenceRaw == "none")
            assert(cal.isDate(exams[0].start, inSameDayAs: date(8)))
            assert(!events.contains { $0.source == "timetable" && cal.isDate($0.start, inSameDayAs: date(8)) })
        }
        let before = Set(try context.fetch(FetchDescriptor<ScheduleEvent>()).map(\.id))
        SchoolFixtureProtocol.failedService = "SchoolSchedule"
        do {
            _ = try await TimetableImporter.importSelections(school: school, grade: 2, selections: selected, into: context)
            assertionFailure("failed schedule fetch must throw")
        } catch {}
        let after = Set(try context.fetch(FetchDescriptor<ScheduleEvent>()).map(\.id))
        assert(before == after)
        SchoolFixtureProtocol.failedService = "hisTimetable"
        SchoolFixtureProtocol.failedClass = "2"   // My class succeeds; missing another class must still preserve existing choices.
        let failed = await TimetableImporter.analyzeGrade(school: school, grade: 2, classNm: "1")
        assert(failed.failed && failed.classTT.isEmpty)
        print("PASS: both import paths keep the supplied exam date and grade, never repeat exams, and preserve data on fetch failure")
    }
}
