import Foundation
import EventKit
import SwiftData

/// 애플 캘린더(EventKit) → Oneul 일회성 가져오기. 오늘부터 90일, (제목·시작) 중복은 건너뜀.
enum CalendarImport {
    enum ImportError: Error { case denied, persistence }

    static func run(context: ModelContext) async throws -> Int {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw ImportError.denied }
        let importContext = ModelContext(context.container)
        importContext.autosaveEnabled = false

        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 90, to: start) ?? start
        let ekEvents = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))

        guard let existing = try? importContext.fetch(FetchDescriptor<ScheduleEvent>()) else {
            throw ImportError.persistence
        }
        var seen = Set(existing.map { "\($0.title)|\(Int($0.start.timeIntervalSince1970))" })
        var added = 0
        for ek in ekEvents {
            guard let s = ek.startDate, let e = ek.endDate else { continue }
            let title = ek.title ?? ""
            let key = "\(title)|\(Int(s.timeIntervalSince1970))"
            guard seen.insert(key).inserted else { continue }
            importContext.insert(ScheduleEvent(title: title, start: s, end: e,
                                               location: ek.location ?? "", reminderMinutes: -1))
            added += 1
        }
        do { try importContext.save() }
        catch { throw ImportError.persistence }
        return added
    }

    // MARK: 구글 캘린더 — 비밀 iCal 주소(.ics) 방식(OAuth 불필요)
    enum GoogleError: Error { case badURL, fetch, empty, persistence }

    static func runGoogleICS(urlString: String, context: ModelContext) async throws -> (added: Int, skippedRecurring: Int) {
        guard var comps = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              comps.host?.isEmpty == false else { throw GoogleError.badURL }
        if comps.scheme == "webcal" { comps.scheme = "https" }
        guard let url = comps.url else { throw GoogleError.badURL }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let text = String(data: data, encoding: .utf8) else { throw GoogleError.fetch }

        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 90, to: start) ?? start

        let parsed = ICS.parse(text)
        guard !parsed.events.isEmpty else { throw GoogleError.empty }
        let importContext = ModelContext(context.container)
        importContext.autosaveEnabled = false

        guard let existing = try? importContext.fetch(FetchDescriptor<ScheduleEvent>()) else {
            throw GoogleError.persistence
        }
        var seen = Set(existing.map { "\($0.title)|\(Int($0.start.timeIntervalSince1970))" })
        var added = 0
        for e in parsed.events where e.start >= start && e.start <= end {
            let key = "\(e.title)|\(Int(e.start.timeIntervalSince1970))"
            guard seen.insert(key).inserted else { continue }
            importContext.insert(ScheduleEvent(title: e.title, start: e.start, end: e.end,
                                               location: e.location, reminderMinutes: -1))
            added += 1
        }
        do { try importContext.save() }
        catch { throw GoogleError.persistence }
        return (added, parsed.skippedRecurring)
    }
}

/// 최소 ICS 파서 — VEVENT의 DTSTART/DTEND/SUMMARY/LOCATION. RRULE(반복)은 1차 미지원(개수만 보고).
enum ICS {
    struct Item { let title: String; let start: Date; let end: Date; let location: String }

    static func parse(_ raw: String) -> (events: [Item], skippedRecurring: Int) {
        // 접힌 줄(개행+공백) 펼치기
        let unfolded = raw.replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
        var events: [Item] = []
        var skipped = 0
        for block in unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            let body = block.components(separatedBy: "END:VEVENT").first ?? ""
            var fields: [String: (params: String, value: String)] = [:]
            for line in body.split(separator: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let head = String(line[..<colon]), value = String(line[line.index(after: colon)...])
                let name = head.components(separatedBy: ";").first ?? head
                fields[name] = (head, value)
            }
            if fields["RRULE"] != nil { skipped += 1; continue }
            guard let ds = fields["DTSTART"], let s = date(ds) else { continue }
            let e = fields["DTEND"].flatMap(date) ?? s.addingTimeInterval(3600)
            let title = unescape(fields["SUMMARY"]?.value ?? "")
            let loc = unescape(fields["LOCATION"]?.value ?? "")
            let allDay = ds.params.contains("VALUE=DATE")
            events.append(Item(title: title, start: s,
                               end: allDay ? e.addingTimeInterval(-1) : max(e, s),   // 종일 DTEND는 exclusive
                               location: loc))
        }
        return (events, skipped)
    }

    private static func date(_ f: (params: String, value: String)) -> Date? {
        let v = f.value
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if f.params.contains("VALUE=DATE") {                 // 종일: 20260706
            fmt.dateFormat = "yyyyMMdd"; fmt.timeZone = .current
            return fmt.date(from: v)
        }
        if v.hasSuffix("Z") {                                 // UTC: 20260706T093000Z
            fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"; fmt.timeZone = TimeZone(identifier: "UTC")
            return fmt.date(from: v)
        }
        fmt.dateFormat = "yyyyMMdd'T'HHmmss"                  // TZID 지정 또는 로컬
        if let tzid = f.params.components(separatedBy: "TZID=").dropFirst().first?
            .components(separatedBy: ";").first,
           let tz = TimeZone(identifier: tzid) { fmt.timeZone = tz } else { fmt.timeZone = .current }
        return fmt.date(from: v)
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\,", with: ",")
         .replacingOccurrences(of: "\\;", with: ";")
         .replacingOccurrences(of: "\\n", with: " ")
         .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
