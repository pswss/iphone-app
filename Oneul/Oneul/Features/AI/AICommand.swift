import Foundation

/// AI가 모델 출력(의미 슬롯)을 해석해 만들어낸 결과.
/// - events: 미리보기 후 적용할 일정 변경(create/update/delete).
/// - actions: 즉시 실행할 동작(외형 전환, 급식·일정 질문 답변).
struct AIResult {
    var events: [ParsedEvent] = []
    var actions: [AIAction] = []

    var isEmpty: Bool { events.isEmpty && actions.isEmpty }
}

/// 미리보기 없이 즉시 처리하는 동작.
enum AIAction {
    case setAppearance(Appearance)
    case mealQuery(date: Date)
    case scheduleQuery(kind: AIQueryKind, day: Date)
    case clarifyDelete(candidates: [DeleteCandidate], prompt: String)   // 삭제 대상이 애매할 때 후보 제시
    case unknown
}

/// 삭제 후보 한 건(어떤 걸 지울지 사용자에게 물을 때).
struct DeleteCandidate: Identifiable, Hashable {
    let id: UUID        // 기존 일정 id
    let title: String
    let start: Date
}

/// 일정·시험 질문의 범위.
enum AIQueryKind {
    case day    // 특정 날의 일정
    case week   // 한 주의 일정
    case exam   // 가장 가까운 시험
}

/// 의미 슬롯(요일/주차/상대일/절대월일 + 24시간 시·분) → 실제 Date 변환.
/// 모델은 ISO 날짜를 만들지 않고, 모든 날짜·시각 계산은 여기서 결정론적으로 한다.
enum AIDateResolver {
    /// 요일 문자열 → Calendar weekday(1=일…7=토). 매칭 안 되면 nil.
    static func weekdayIndex(_ s: String) -> Int? {
        switch s.trimmingCharacters(in: .whitespaces).lowercased() {
        case "sun", "일", "일요일": return 1
        case "mon", "월", "월요일": return 2
        case "tue", "화", "화요일": return 3
        case "wed", "수", "수요일": return 4
        case "thu", "목", "목요일": return 5
        case "fri", "금", "금요일": return 6
        case "sat", "토", "토요일": return 7
        default: return nil
        }
    }

    /// "mon,wed,fri" → {2,4,6}.
    static func weekdaySet(_ csv: String) -> Set<Int> {
        Set(csv.split(separator: ",").compactMap { weekdayIndex(String($0)) })
    }

    /// 날짜만 해석(시각 제외). 우선순위: 요일+주차 → 절대 월/일 → 상대일.
    static func resolveDate(relativeDay: Int, weekday: String, weekOffset: Int,
                            month: Int, day: Int, now: Date, cal: Calendar = .current) -> Date {
        let today = cal.startOfDay(for: now)

        // 1) 요일 + 주차 ("다음주 월요일")
        if let wd = weekdayIndex(weekday) {
            let todayWd = cal.component(.weekday, from: today)      // 1=일…7=토
            let mondayOffset = (todayWd + 5) % 7                     // 이번 주 월요일까지
            let monday = cal.date(byAdding: .day, value: -mondayOffset, to: today) ?? today
            let targetOffset = (wd + 5) % 7                          // 월=0…일=6
            return cal.date(byAdding: .day, value: targetOffset + max(0, weekOffset) * 7, to: monday) ?? today
        }

        // 2) 절대 월/일 (이미 지났으면 내년)
        if (1...12).contains(month) && (1...31).contains(day) {
            var comps = cal.dateComponents([.year], from: today)
            comps.month = month; comps.day = day
            if let d = cal.date(from: comps) {
                if d < today {
                    comps.year = (comps.year ?? cal.component(.year, from: today)) + 1
                    return cal.date(from: comps) ?? d
                }
                return d
            }
        }

        // 3) 상대일(기본 오늘)
        return cal.date(byAdding: .day, value: relativeDay, to: today) ?? today
    }

    /// 날짜 + 시각 해석. hasTime=false면 시각 단서가 없던 것(새 일정 생성 거부 신호로 사용).
    static func resolve(relativeDay: Int, weekday: String, weekOffset: Int,
                        month: Int, day: Int,
                        startHour: Int, startMinute: Int, endHour: Int, endMinute: Int,
                        now: Date, cal: Calendar = .current) -> (start: Date, end: Date, hasTime: Bool) {
        let baseDay = resolveDate(relativeDay: relativeDay, weekday: weekday, weekOffset: weekOffset,
                                  month: month, day: day, now: now, cal: cal)
        let hasTime = (0...23).contains(startHour)
        let start = hasTime
            ? (cal.date(bySettingHour: startHour, minute: clampMinute(startMinute), second: 0, of: baseDay) ?? baseDay)
            : baseDay
        let end: Date
        if hasTime && (0...23).contains(endHour) {
            var e = cal.date(bySettingHour: endHour, minute: clampMinute(endMinute), second: 0, of: baseDay) ?? start
            if e <= start { e = start.addingTimeInterval(3600) }   // 종료 ≤ 시작이면 +1시간
            end = e
        } else {
            end = start.addingTimeInterval(3600)
        }
        return (start, end, hasTime)
    }

    private static func clampMinute(_ m: Int) -> Int { max(0, min(59, m)) }
}

/// 입력 텍스트에서 직접 뽑은 한국어 날짜·시각(작은 모델보다 신뢰도 높음).
/// 값이 있으면 단일 명령의 슬롯을 덮어써 정확도를 높인다. 요일은 오늘 기준 일수(relativeDay)로 환산.
struct AIKoreanDateTime {
    var relativeDay: Int?
    var endRelativeDay: Int?    // 기간(여러 날) 일정의 종료일(오늘 기준 일수). 있으면 멀티데이.
    var month: Int?
    var day: Int?
    var startHour: Int?
    var startMinute: Int?
    var endHour: Int?
    var endMinute: Int?
}

enum AIKoreanDate {
    static func parse(_ text: String, now: Date, cal: Calendar = .current) -> AIKoreanDateTime {
        var r = AIKoreanDateTime()
        let today = cal.startOfDay(for: now)

        // 기간(여러 날) 일정: "A부터 B까지" / "A~B" / "A에서 B까지" (양쪽 다 날짜일 때만)
        if let (startPart, endPart) = rangeParts(text),
           let startDate = dayFromKeywords(startPart, today: today, cal: cal),
           let endDate = dayFromKeywords(endPart, today: today, cal: cal),
           endDate > startDate {
            r.relativeDay = cal.dateComponents([.day], from: today, to: startDate).day
            r.endRelativeDay = cal.dateComponents([.day], from: today, to: endDate).day
            if let st = rangeTime(startPart) { r.startHour = st.h; r.startMinute = st.m }   // 시작 시각(말했으면)
            if let et = rangeTime(endPart) { r.endHour = et.h; r.endMinute = et.m }         // 종료 시각(말했으면)
            return r
        }

        // 단일 날짜: 폭넓은 한국어 날짜 해석 → relativeDay(오늘 기준 일수)로 통일
        if let d = dayFromKeywords(text, today: today, cal: cal) {
            r.relativeDay = cal.dateComponents([.day], from: today, to: d).day
        }

        // 시각(범위가 아니면 단일 시각)
        if let t = parseSingleTime(text) { r.startHour = t.h; r.startMinute = t.m }
        return r
    }

    /// "HH:MM" 또는 "N시[반][M분]" + 오전/오후. 확실할 때만 값을 돌려주고, 모호한 맨숫자 시각(예: "3시")은
    /// 모델 판단(낮 활동→오후)에 맡기려 nil. 범위("~","부터","N-M")도 nil.
    private static func parseSingleTime(_ text: String) -> (h: Int, m: Int)? {
        if text.contains("~") || text.contains("부터") ||
            text.range(of: #"\d\s*-\s*\d"#, options: .regularExpression) != nil { return nil }

        // HH:MM — 명확
        if let r = text.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) {
            let parts = text[r].split(separator: ":")
            if let h = Int(parts[0]), let m = Int(parts[1]), h < 24, m < 60 { return (h, m) }
        }

        guard let r = text.range(of: #"\d{1,2}\s*시"#, options: .regularExpression),
              var h = Int(text[r].prefix { $0.isNumber }), h < 24 else { return nil }
        var minute = 0
        if text.contains("반") { minute = 30 }
        if let mr = text.range(of: #"시\s*\d{1,2}\s*분"#, options: .regularExpression) {
            minute = Int(text[mr].filter { $0.isNumber }) ?? 0
        }

        let pm = ["오후", "저녁", "밤"].contains { text.contains($0) }
        let am = ["오전", "새벽", "아침"].contains { text.contains($0) }
        let noon = text.contains("정오"), midnight = text.contains("자정")
        if pm, h < 12 { h += 12 }
        if am, h == 12 { h = 0 }
        if noon { h = 12 }
        if midnight { h = 0 }

        // 오전/오후·정오·자정 표시가 있거나, 이미 24시간제(13시 이상)거나, HH:MM이면 확실 → 덮어씀.
        // 맨숫자 1~12시(표시 없음)는 모호 → 모델에 맡김.
        let confident = pm || am || noon || midnight || h >= 13
        return confident ? (h, minute) : nil
    }

    /// 기간 일정 부분의 시각(말한 그대로, 모호해도 face value). "HH:MM" 또는 "N시" + 오전/오후.
    private static func rangeTime(_ text: String) -> (h: Int, m: Int)? {
        if let r = text.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) {
            let p = text[r].split(separator: ":")
            if let h = Int(p[0]), let m = Int(p[1]), h < 24, m < 60 { return (h, m) }
        }
        guard let r = text.range(of: #"\d{1,2}\s*시"#, options: .regularExpression),
              var h = Int(text[r].prefix { $0.isNumber }), h < 24 else { return nil }
        var m = 0
        if text.contains("반") { m = 30 }
        if let mr = text.range(of: #"시\s*\d{1,2}\s*분"#, options: .regularExpression) {
            m = Int(text[mr].filter { $0.isNumber }) ?? 0
        }
        if ["오후", "저녁", "밤"].contains(where: text.contains), h < 12 { h += 12 }
        if ["오전", "새벽", "아침"].contains(where: text.contains), h == 12 { h = 0 }
        return (h, m)
    }

    /// "A부터 B까지" / "A~B" / "A에서 B까지" → (앞, 뒤). 범위 표현이 없으면 nil.
    private static func rangeParts(_ text: String) -> (String, String)? {
        if let r = text.range(of: "~") { return (String(text[..<r.lowerBound]), String(text[r.upperBound...])) }
        if let r = text.range(of: "부터") { return (String(text[..<r.lowerBound]), String(text[r.upperBound...])) }
        if text.contains("까지"), let r = text.range(of: "에서") {
            return (String(text[..<r.lowerBound]), String(text[r.upperBound...]))
        }
        return nil
    }

    /// 텍스트 조각에서 한국어 날짜 표현을 폭넓게 해석해 그 날(자정)을 반환. 못 찾으면 nil.
    /// 지원: 오늘/내일/모레/글피/그글피/어제/그제, N(일·주·달) 후·뒤·전, 한글 일수(사흘·열흘 등),
    ///       (이번/다음/다다음)주 + 요일, 막연 요일, 주말, 월말·말일, N월 M일, M/D,
    ///       (이번/다음/다다음) 달 M일, 그냥 "M일"(이번 달; 지났으면 다음 달).
    private static func dayFromKeywords(_ text: String, today: Date, cal: Calendar) -> Date? {
        func add(_ comp: Calendar.Component, _ v: Int) -> Date? { cal.date(byAdding: comp, value: v, to: today) }
        func num(_ s: Substring) -> Int { Int(s.filter(\.isNumber)) ?? 0 }

        // 1) N(일/주/달/개월) 후·뒤·전
        if let r = text.range(of: #"\d{1,2}\s*(일|주|주일|달|개월)\s*(후|뒤|있다가|지나)"#, options: .regularExpression) {
            let s = text[r]; let n = num(s)
            if s.contains("주") { return add(.day, n * 7) }
            if s.contains("달") || s.contains("개월") { return add(.month, n) }
            return add(.day, n)
        }
        if let r = text.range(of: #"\d{1,2}\s*(일|주|주일|달|개월)\s*전"#, options: .regularExpression) {
            let s = text[r]; let n = num(s)
            if s.contains("주") { return add(.day, -n * 7) }
            if s.contains("달") || s.contains("개월") { return add(.month, -n) }
            return add(.day, -n)
        }
        // 한글 일수 + 후/뒤/전
        let counts: [(String, Int)] = [("열흘", 10), ("아흐레", 9), ("여드레", 8), ("이레", 7),
                                       ("엿새", 6), ("닷새", 5), ("나흘", 4), ("사흘", 3), ("이틀", 2)]
        for (w, n) in counts where text.contains(w) {
            if text.contains("뒤") || text.contains("후") || text.contains("있다가") || text.contains("지나") { return add(.day, n) }
            if text.contains("전") { return add(.day, -n) }
        }

        // 2) 주차 + 요일 / 막연 요일 / 주말
        var weekOffset: Int?
        if text.contains("다다음주") || text.contains("다다음 주") { weekOffset = 2 }
        else if text.contains("다음주") || text.contains("다음 주") || text.contains("담주") || text.contains("담 주") { weekOffset = 1 }
        else if text.contains("이번주") || text.contains("이번 주") || text.contains("금주") { weekOffset = 0 }

        if text.contains("주말") {   // 다가오는 토요일(+ 주차)
            let todayWd = cal.component(.weekday, from: today)
            if let sat = add(.day, (7 - todayWd + 7) % 7) { return cal.date(byAdding: .day, value: (weekOffset ?? 0) * 7, to: sat) }
        }
        let wdMap: [(String, Int)] = [("월요일", 2), ("화요일", 3), ("수요일", 4),
                                      ("목요일", 5), ("금요일", 6), ("토요일", 7), ("일요일", 1)]
        if let wd = wdMap.first(where: { text.contains($0.0) })?.1 {
            let todayWd = cal.component(.weekday, from: today)
            if let off = weekOffset {
                let mondayOffset = (todayWd + 5) % 7
                if let monday = cal.date(byAdding: .day, value: -mondayOffset + off * 7, to: today) {
                    return cal.date(byAdding: .day, value: (wd + 5) % 7, to: monday)
                }
            } else {
                return add(.day, (wd - todayWd + 7) % 7)   // 다가오는 그 요일
            }
        }

        // 3) 월말 / 말일
        if text.contains("월말") || text.contains("말일") {
            let base = (text.contains("다음") || text.contains("담")) ? (add(.month, 1) ?? today) : today
            if let iv = cal.dateInterval(of: .month, for: base) { return cal.date(byAdding: .day, value: -1, to: iv.end) }
        }

        // 4) 절대 N월 M일 / M/D (지났으면 내년)
        func absolute(_ m: Int, _ d: Int) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            var c = cal.dateComponents([.year], from: today); c.month = m; c.day = d
            guard let date = cal.date(from: c) else { return nil }
            if date < today { c.year = (c.year ?? 0) + 1; return cal.date(from: c) }
            return date
        }
        if let r = text.range(of: #"(\d{1,2})\s*월\s*(\d{1,2})\s*일"#, options: .regularExpression) {
            let n = String(text[r]).components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if n.count >= 2, let d = absolute(n[0], n[1]) { return d }
        }
        if let r = text.range(of: #"\d{1,2}\s*/\s*\d{1,2}"#, options: .regularExpression) {
            let n = String(text[r]).components(separatedBy: CharacterSet(charactersIn: "/ ")).compactMap { Int($0) }
            if n.count >= 2, let d = absolute(n[0], n[1]) { return d }
        }

        // 5) (이번/다음/다다음) 달 M일 또는 그냥 "M일"(이번 달; 지났으면 다음 달)
        if let r = text.range(of: #"(\d{1,2})\s*일"#, options: .regularExpression) {
            let d = num(text[r])
            if (1...31).contains(d) {
                var shift = 0
                if text.contains("다다음 달") || text.contains("다다음달") { shift = 2 }
                else if text.contains("다음 달") || text.contains("다음달") || text.contains("담달") || text.contains("담 달") { shift = 1 }
                let base = add(.month, shift) ?? today
                var c = cal.dateComponents([.year, .month], from: base); c.day = d
                if let date = cal.date(from: c) {
                    if shift == 0 && date < today { c.month = (c.month ?? 1) + 1; return cal.date(from: c) }   // 지났으면 다음 달
                    return date
                }
            }
        }

        // 6) "다음 주" 등(요일 미지정) → 그 주 월요일
        if let off = weekOffset, off >= 1 {
            let todayWd = cal.component(.weekday, from: today)
            return add(.day, -((todayWd + 5) % 7) + off * 7)
        }

        // 7) 상대일 단어
        if text.contains("그글피") { return add(.day, 4) }
        if text.contains("내일모레") || text.contains("모레") { return add(.day, 2) }
        if text.contains("글피") { return add(.day, 3) }
        if text.contains("내일") { return add(.day, 1) }
        if text.contains("그제") || text.contains("그저께") { return add(.day, -2) }
        if text.contains("어제") { return add(.day, -1) }
        if text.contains("오늘") { return today }
        return nil
    }

    /// 한 문장의 여러 일정을 쉼표·'그리고'로 분리(명령마다 정확히 보정하기 위해).
    static func segments(_ text: String) -> [String] {
        var t = text
        for sep in ["그리고나서", "그리고는", "그리고", "그 다음에", "그다음에", "그 담에", "그담에"] {
            t = t.replacingOccurrences(of: sep, with: ",")
        }
        return t.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" || $0 == "·" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

}
