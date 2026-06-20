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
    case unknown
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

        // 주차 키워드
        var weekOffset: Int?
        if text.contains("다다음주") || text.contains("다다음 주") { weekOffset = 2 }
        else if text.contains("다음주") || text.contains("다음 주") || text.contains("담주") { weekOffset = 1 }
        else if text.contains("이번주") || text.contains("이번 주") { weekOffset = 0 }

        // 요일(전체 표기)
        let wdMap: [(String, Int)] = [("월요일", 2), ("화요일", 3), ("수요일", 4),
                                      ("목요일", 5), ("금요일", 6), ("토요일", 7), ("일요일", 1)]
        let weekday = wdMap.first(where: { text.contains($0.0) })?.1

        if let wd = weekday {
            let todayWd = cal.component(.weekday, from: today)   // 1=일…7=토
            if let off = weekOffset {
                // 명시적 주차: 그 주의 해당 요일
                let mondayOffset = (todayWd + 5) % 7
                if let monday = cal.date(byAdding: .day, value: -mondayOffset + off * 7, to: today),
                   let target = cal.date(byAdding: .day, value: (wd + 5) % 7, to: monday) {
                    r.relativeDay = cal.dateComponents([.day], from: today, to: target).day
                }
            } else {
                // 막연한 요일: 오늘 포함 다가오는 그 요일
                r.relativeDay = (wd - todayWd + 7) % 7
            }
        } else {
            if text.contains("모레") || text.contains("내일모레") { r.relativeDay = 2 }
            else if text.contains("글피") { r.relativeDay = 3 }
            else if text.contains("내일") { r.relativeDay = 1 }
            else if text.contains("어제") { r.relativeDay = -1 }
            else if text.contains("오늘") { r.relativeDay = 0 }
        }

        // 절대 월/일 (요일보다 우선)
        if let m = text.range(of: #"(\d{1,2})\s*월\s*(\d{1,2})\s*일"#, options: .regularExpression) {
            let nums = String(text[m]).components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            if nums.count >= 2 { r.month = nums[0]; r.day = nums[1]; r.relativeDay = nil }
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
