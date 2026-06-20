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
