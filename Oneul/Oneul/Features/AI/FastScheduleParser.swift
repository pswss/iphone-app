import Foundation
#if canImport(MapKit)
import MapKit
#endif

/// 규칙 기반 '빠른 경로' 파서 — 온디바이스 모델을 부르기 전에 먼저 시도한다.
///
/// 목적: 단순한 "일정 추가" 문장(특히 날짜/시간/내용이 규칙적인 표·여러 줄 입력)은
/// 모델 없이 즉시·정확하게 만든다. 확신이 안 서면(질문·수정·삭제·외형 변경·모호한 문장) nil을
/// 돌려 기존 Apple Intelligence 경로로 폴백한다.
///
/// 핵심 규칙: **입력 전체를 깔끔히 소화했을 때만** 이벤트를 돌려준다.
/// 한 줄이라도 이해 못 하면(붙일 곳 없는 내용, 미해석 숫자 잔여물 등) 전체를 nil로 폴백 →
/// 모델이 처리 → "여러 줄을 보내도 모두 정확히 추가"를 보장(일부만 넣고 조용히 버리지 않음).
enum FastScheduleParser {

    // MARK: 공개 진입점

    /// 비동기(장소 검증 포함). 확신하면 AIResult, 아니면 nil(→ 모델 폴백).
    static func tryParse(text: String, now: Date, existing: [ExistingEvent],
                         cal: Calendar = .current, context: AIParseContext = AIParseContext()) async -> AIResult? {
        guard var events = parseEvents(text: text, now: now, cal: cal, context: context), !events.isEmpty else { return nil }
        for i in events.indices where !events[i].location.isEmpty {
            events[i].location = await validatePlace(events[i].location)
        }
        return AIResult(events: events, actions: [])
    }

    /// 규칙 기반 '수정' 빠른 경로 — "수학 9시로 바꿔줘", "치과 내일로 옮겨줘" 같은 단순 시간·날짜 변경을
    /// 모델 없이 즉시 처리한다. 대상 일정(제목 일치)이나 새 값이 확실치 않으면 nil(→ 모델 폴백).
    /// 작은 모델이 수정 요청을 삭제+생성으로 오해해 엉뚱한 일정을 지우던 버그의 근본 대책.
    static func tryParseEdit(text: String, now: Date, existing: [ExistingEvent],
                             cal: Calendar = .current) -> AIResult? {
        let t = normalizeKoreanTime(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !t.isEmpty, !t.contains("\n"), !existing.isEmpty else { return nil }
        guard hasUpdateCue(t), !hasDeleteCue(t), !t.contains("?"), !t.contains("？") else { return nil }

        // 새 시각: '…로/으로' 바로 앞의 시각만 새 값("8시 수학 9시로 바꿔" → 9시)
        let timeToPat = #"(오전|오후|저녁|밤|새벽|아침)?\s*(\d{1,2})\s*시\s*(?:(\d{1,2})\s*분\s*|(반)\s*)?(?:으로|로)"#
        var newTime: (h: Int, m: Int, explicit: Bool)?
        if let g = match(t, timeToPat), let hRaw = Int(g[2]), hRaw < 24 {
            var h = hRaw
            var explicit = hRaw >= 13
            if ["오후", "저녁", "밤"].contains(g[1]) { if h < 12 { h += 12 }; explicit = true }
            if ["오전", "새벽", "아침"].contains(g[1]) { if h == 12 { h = 0 }; explicit = true }
            let m = g[4] == "반" ? 30 : min(59, Int(g[3]) ?? 0)
            newTime = (h, m, explicit)
        }

        // 대상: 제목이 입력에 통째로 든 기존 일정(가장 긴 제목 우선)
        let titled = existing.filter { !$0.title.isEmpty && t.contains($0.title) }
        guard let bestLen = titled.map({ $0.title.count }).max() else { return nil }
        let title = titled.first(where: { $0.title.count == bestLen })!.title
        var cands = titled.filter { $0.title == title }
        guard let titleRange = t.range(of: title) else { return nil }
        let before = String(t[..<titleRange.lowerBound])
        var after = String(t[titleRange.upperBound...])
        if let r = after.range(of: timeToPat, options: .regularExpression) { after.removeSubrange(r) }

        // 새 날짜: (a) '…로/으로'가 붙은 날짜("내일로", "13일로") (b) 제목 뒤의 날짜("수학 내일 9시로")
        let dateToPat = #"((?:다다음|다음|이번)\s*주(?:\s*[월화수목금토일]요일)?|오늘|내일모레|내일|모레|글피|[월화수목금토일]요일|(?<![가-힣0-9])[월화수목금토일]|\d{1,2}\s*월\s*\d{1,2}\s*일|(?<!\d)\d{1,2}\s*/\s*\d{1,2}|(?<!\d)\d{1,2}\s*일)\s*(?:으로|로)"#
        var newDay: Date?
        let today = cal.startOfDay(for: now)
        if let g = match(t, dateToPat), let rd = AIKoreanDate.parse(g[1], now: now, cal: cal).relativeDay {
            newDay = cal.date(byAdding: .day, value: rd, to: today)
        } else if let rd = AIKoreanDate.parse(after, now: now, cal: cal).relativeDay {
            newDay = cal.date(byAdding: .day, value: rd, to: today)
        }
        guard newTime != nil || newDay != nil else { return nil }

        // 같은 제목이 여럿이면 제목 앞의 날짜("금요일 수학…")·기존 시각("8시 수학…")으로 좁힘
        if let qd = AIKoreanDate.parse(before, now: now, cal: cal).relativeDay,
           let day = cal.date(byAdding: .day, value: qd, to: today) {
            let narrowed = cands.filter { cal.isDate($0.start, inSameDayAs: day) }
            if !narrowed.isEmpty { cands = narrowed }
        }
        if let old = hourToken(before, bareOK: false) {
            let hs: Set<Int> = [old.h, resolve1(old).0, old.h < 12 ? old.h + 12 : old.h]
            let narrowed = cands.filter { hs.contains(cal.component(.hour, from: $0.start)) }
            if !narrowed.isEmpty { cands = narrowed }
        }
        guard let target = cands.sorted(by: { $0.start < $1.start }).first else { return nil }

        let baseDay = cal.startOfDay(for: newDay ?? target.start)
        var h = cal.component(.hour, from: target.start)
        var m = cal.component(.minute, from: target.start)
        if let nt = newTime {
            if nt.explicit { h = nt.h } else {
                let alt = nt.h < 12 ? nt.h + 12 : nt.h
                h = abs(nt.h - h) <= abs(alt - h) ? nt.h : alt   // 맨숫자는 원래 시각과 가까운 오전/오후 해석
            }
            m = nt.m
        }
        let start = cal.date(bySettingHour: h, minute: m, second: 0, of: baseDay) ?? target.start
        let dur = target.end.timeIntervalSince(target.start)
        let end = start.addingTimeInterval(dur > 0 ? dur : 3600)
        return AIResult(events: [ParsedEvent(title: target.title, start: start, end: end,
                                             location: target.location, action: .update, targetID: target.id)],
                        actions: [])
    }

    // MARK: - 빠른 삭제/급식/질문/외형 경로 (모델 불필요 — AI 미지원 기기에서도 동작, 즉시 응답)

    /// 제목 기반 삭제("수학 지워줘", "수학 전부 삭제") — 규칙으로 즉시.
    /// 대상이 여럿이면 clarifyDelete(후보 제시), 못 찾으면 nil(→ 모델).
    static func tryParseDelete(text: String, now: Date, existing: [ExistingEvent],
                               cal: Calendar = .current) -> AIResult? {
        let t = normalizeKoreanTime(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !t.isEmpty, !t.contains("\n"), hasDeleteCue(t), !existing.isEmpty else { return nil }
        // 수정·추가가 섞인 복합 문장은 모델로("수학 삭제하고 영어 추가해줘")
        guard !hasUpdateCue(t), !["추가", "넣어", "등록", "만들"].contains(where: t.contains) else { return nil }
        guard let kw = deleteKeyword(t, existing) else { return nil }

        let bulk = ["전부", "모두", "싹", "몽땅", "죄다", "전체"].contains { t.contains($0) }
            || has(t, #"다\s*(지워|지우|삭제|없애|빼)"#)
        if bulk {   // 같은 제목 일괄 삭제 — 미리보기에 "N개 삭제" 경고 후 적용
            AIDeleteContext.lastKeyword = kw
            AIDeleteContext.lastChosen = nil
            return AIResult(events: [ParsedEvent(title: kw, start: now, end: now,
                                                 location: "", action: .delete, targetID: nil)], actions: [])
        }

        var cands = existing.filter { !$0.title.isEmpty && ($0.title.contains(kw) || kw.contains($0.title)) }
            .sorted { $0.start < $1.start }
        // 날짜 언급으로 좁힘("금요일 수학 지워줘")
        if let rd = AIKoreanDate.parse(t, now: now, cal: cal).relativeDay,
           let day = cal.date(byAdding: .day, value: rd, to: cal.startOfDay(for: now)) {
            let narrowed = cands.filter { cal.isDate($0.start, inSameDayAs: day) }
            if !narrowed.isEmpty { cands = narrowed }
        }
        // 시각 언급으로 좁힘("8시 수학 지워줘")
        if let old = hourToken(t, bareOK: false) {
            let hs: Set<Int> = [old.h, resolve1(old).0, old.h < 12 ? old.h + 12 : old.h]
            let narrowed = cands.filter { hs.contains(cal.component(.hour, from: $0.start)) }
            if !narrowed.isEmpty { cands = narrowed }
        }
        AIDeleteContext.lastKeyword = kw
        if cands.count > 1 {
            AIDeleteContext.lastChosen = nil
            return AIResult(events: [], actions: [.clarifyDelete(
                candidates: cands.map { DeleteCandidate(id: $0.id, title: $0.title, start: $0.start) },
                prompt: AppLanguage.shared.tr("어떤 것을 삭제할까요?"))])
        }
        guard let target = cands.first else { return nil }
        AIDeleteContext.lastChosen = target.id
        return AIResult(events: [ParsedEvent(title: target.title, start: target.start, end: target.end,
                                             location: target.location, action: .delete, targetID: target.id)],
                        actions: [])
    }

    /// 전체 삭제("일정 싹다 지워줘") — 특정 제목·날짜 없이 일정 전체를 지우려는 요청인지.
    /// 파괴적이므로 삭제 단어 + 전부류 단어 + '일정/스케줄/약속' 명시가 모두 있어야 한다.
    static func isDeleteAll(_ text: String) -> Bool {
        guard hasDeleteCue(text), !hasUpdateCue(text) else { return false }
        let wholesale = ["전부", "모두", "싹", "몽땅", "죄다", "전체"].contains { text.contains($0) }
            || has(text, #"다\s*(지워|지우|삭제|없애|빼)"#)
        guard wholesale else { return false }
        return ["일정", "스케줄", "약속"].contains { text.contains($0) }
    }

    /// 삭제 키워드: 입력에 통째로 든 기존 제목(가장 긴 것) 우선, 없으면 제목에 들어간 단어.
    static func deleteKeyword(_ text: String, _ existing: [ExistingEvent]) -> String? {
        if let t = existing.filter({ !$0.title.isEmpty && text.contains($0.title) })
            .map(\.title).max(by: { $0.count < $1.count }) { return t }
        let words = text.components(separatedBy: CharacterSet(charactersIn: " ,.\n")).filter { $0.count >= 2 }
        return words.first(where: { w in existing.contains { $0.title.contains(w) } })
    }

    /// "아니 그거 말고", "다른거" 같은 거부·재요청 짧은 문구인지.
    static func isRejectionFollowup(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        let cues = ["그거말고", "그게아니", "다른거", "다른걸", "딴거", "말고다른", "아니다른", "그말고"]
        if cues.contains(where: t.contains) { return true }
        return t.count <= 9 && (t.hasPrefix("아니") || t.hasSuffix("말고"))
    }

    /// 급식/식단 질문 — 날짜만 해석하면 됨(조회·답변은 뷰가 NEIS로).
    static func tryParseMeal(text: String, now: Date, cal: Calendar = .current) -> AIResult? {
        guard text.contains("급식") || text.contains("식단") else { return nil }
        let rd = AIKoreanDate.parse(text, now: now, cal: cal).relativeDay ?? 0
        let day = cal.date(byAdding: .day, value: rd, to: cal.startOfDay(for: now)) ?? now
        return AIResult(events: [], actions: [.mealQuery(date: day)])
    }

    /// 일정·시험 질문("내일 뭐 있어?", "시험 언제야?") — 명확한 패턴만, 아니면 nil(→ 모델).
    static func tryParseQuery(text: String, now: Date, cal: Calendar = .current) -> AIResult? {
        let t = text
        guard !t.contains("급식"), !t.contains("식단") else { return nil }   // 급식은 tryParseMeal이
        // 시험 D-Day
        if (t.contains("시험") || t.contains("수능")),
           ["언제", "며칠", "몇일", "얼마나", "디데이", "d-", "D-"].contains(where: t.contains) {
            return AIResult(events: [], actions: [.scheduleQuery(kind: .exam, day: now)])
        }
        // 일정 질문 단서(명확한 것만)
        let asksSchedule = ["뭐 있", "뭐있", "뭐가 있", "무슨 일정", "일정 알려", "일정 뭐",
                            "스케줄 알려", "스케줄 뭐", "몇 개", "몇개있", "일정 있"].contains { t.contains($0) }
        guard asksSchedule else { return nil }
        let rd = AIKoreanDate.parse(t, now: now, cal: cal).relativeDay
        let day = rd.flatMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now)) } ?? now
        let weekWord = ["이번주", "이번 주", "다음주", "다음 주", "금주"].contains { t.contains($0) }
        let hasWeekday = has(t, #"[월화수목금토일]요일"#) || has(t, #"(?<![가-힣0-9])[월화수목금토일](?![가-힣])"#)
        let kind: AIQueryKind = (weekWord && !hasWeekday) ? .week : .day
        return AIResult(events: [], actions: [.scheduleQuery(kind: kind, day: day)])
    }

    /// 외형 전환("다크모드로 바꿔줘") — 모드/테마 단어 + 색상어일 때만.
    static func tryParseAppearance(_ text: String) -> AIResult? {
        guard !text.contains("?"), !text.contains("？") else { return nil }
        let t = text.replacingOccurrences(of: " ", with: "")
        guard t.contains("모드") || t.contains("테마") else { return nil }
        let mode: Appearance
        if t.contains("다크") || t.contains("어두") || t.contains("야간") { mode = .dark }
        else if t.contains("라이트") || t.contains("밝") || t.contains("주간") { mode = .light }
        else if t.contains("시스템") || t.contains("자동") { mode = .system }
        else { return nil }
        return AIResult(events: [], actions: [.setAppearance(mode)])
    }

    /// 기간 범위 삭제 요청("다음 주 일정 다 지워줘"). [from, to) 반환. 아니면 nil.
    struct RangeDelete { var from: Date; var to: Date }

    /// 삭제 단어 + '전부/다/모두/일정' 단서 + 날짜 범위(하루/주/주말/달)가 모두 있어야 범위 삭제로 본다.
    /// "수학 전부 삭제"(제목 일괄)나 "내일 회의 지워줘"(단건)는 nil → 기존 제목 기반 경로.
    static func tryParseRangeDelete(text: String, now: Date, existing: [ExistingEvent] = [],
                                    cal: Calendar = .current) -> RangeDelete? {
        let t = text
        guard hasDeleteCue(t) else { return nil }
        // 기존 일정 제목이 문장에 들어 있으면("내일 수학 전부 지워줘") 제목 기반 삭제가 우선 — 날짜 전체 오폭 방지
        guard !existing.contains(where: { $0.title.count >= 2 && t.contains($0.title) }) else { return nil }
        let wholesale = ["전부", "모두", "몽땅", "싹", "죄다", "전체", "일정"].contains { t.contains($0) }
            || has(t, #"다\s*(지워|지우|삭제|없애|빼|취소)"#)
        guard wholesale else { return nil }

        let today = cal.startOfDay(for: now)
        let todayWd = cal.component(.weekday, from: today)
        var weekOff: Int? = nil
        if t.contains("다다음주") || t.contains("다다음 주") { weekOff = 2 }
        else if t.contains("다음주") || t.contains("다음 주") || t.contains("담주") { weekOff = 1 }
        else if t.contains("이번주") || t.contains("이번 주") || t.contains("금주") { weekOff = 0 }

        // 주말: 다가오는 토요일(+주차) ~ 일요일 끝
        if t.contains("주말") {
            if let sat = cal.date(byAdding: .day, value: (7 - todayWd + 7) % 7 + (weekOff ?? 0) * 7, to: today),
               let end = cal.date(byAdding: .day, value: 2, to: sat) {
                return RangeDelete(from: max(sat, today), to: end)
            }
        }
        let hasWeekday = has(t, #"[월화수목금토일]요일"#) || has(t, #"(?<![가-힣0-9])[월화수목금토일](?![가-힣])"#)
        if !hasWeekday {
            // 주 단위(요일 미지정): 그 주 월요일 ~ 다음 월요일. 과거 요일은 제외(오늘부터).
            if let off = weekOff,
               let monday = cal.date(byAdding: .day, value: -((todayWd + 5) % 7) + off * 7, to: today),
               let end = cal.date(byAdding: .day, value: 7, to: monday) {
                return RangeDelete(from: max(monday, today), to: end)
            }
            // 달 단위
            var monthOff: Int? = nil
            if t.contains("다다음달") || t.contains("다다음 달") { monthOff = 2 }
            else if t.contains("다음달") || t.contains("다음 달") || t.contains("담달") { monthOff = 1 }
            else if t.contains("이번달") || t.contains("이번 달") { monthOff = 0 }
            if let off = monthOff, let base = cal.date(byAdding: .month, value: off, to: today),
               let iv = cal.dateInterval(of: .month, for: base) {
                return RangeDelete(from: max(iv.start, today), to: iv.end)
            }
        }
        // 하루 단위(오늘/내일/요일/N월 N일 …) — 명시된 과거 날짜(어제)는 그대로 허용
        if let rd = AIKoreanDate.parse(t, now: now, cal: cal).relativeDay,
           let day = cal.date(byAdding: .day, value: rd, to: today),
           let next = cal.date(byAdding: .day, value: 1, to: day) {
            return RangeDelete(from: day, to: next)
        }
        return nil
    }

    // MARK: 순수 파싱 코어 (테스트 대상 — 네트워크·장소검증 없음)

    /// 한글 숫자 시각 → 아라비아 숫자("한시 병원" → "1시 병원", "열두시 반" → "12시 반").
    /// 음성 입력이 한글 수사로 들어와 파서·모델 모두 놓치던 문제의 근본 수정.
    static func normalizeKoreanTime(_ text: String) -> String {
        let map: [(String, String)] = [   // 긴 것 먼저(열두/열한이 '열'에 먹히지 않게)
            ("열두", "12"), ("열한", "11"), ("열", "10"), ("아홉", "9"), ("여덟", "8"),
            ("일곱", "7"), ("여섯", "6"), ("다섯", "5"), ("네", "4"), ("세", "3"), ("두", "2"), ("한", "1"),
        ]
        var out = text
        for (ko, num) in map {
            // 앞이 한글이 아니고(단어 시작), 뒤가 '시'(단 '시간'·'시장' 등 제외)일 때만
            let pattern = "(?<![가-힣])\(ko)\\s*시(?![간장])"
            out = out.replacingOccurrences(of: pattern, with: "\(num)시", options: .regularExpression)
        }
        return out
    }

    static func parseEvents(text: String, now: Date, cal: Calendar = .current,
                            context: AIParseContext = AIParseContext()) -> [ParsedEvent]? {
        let trimmed = normalizeKoreanTime(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !trimmed.isEmpty else { return nil }

        if isNonCreateIntent(trimmed) { return nil }   // 질문/수정/삭제/외형/후속 → 모델

        let segs = segment(trimmed)
        guard !segs.isEmpty else { return nil }

        let yearShift = absoluteYearShift(segs, now: now, cal: cal)

        var events: [ParsedEvent] = []
        var carryDay: Date? = nil
        var pendingTime: TimeSpan? = nil
        var unplaced = 0

        for seg in segs {
            let dateHint = detectDate(seg, now: now, cal: cal, yearShift: yearShift)
            let time = fastTime(seg)
            let title = extractTitle(seg)

            if let d = dateHint { carryDay = d }
            if let t = time { pendingTime = t }

            if title.isEmpty { continue }        // 날짜/시각만 있는 줄 → 이월·대기만 갱신
            if isNoiseHeader(title) { continue }  // "날짜/시간/내용" 표 머리글
            if hasParseResidue(title) {           // 미해석 날짜·시각 숫자가 제목에 남음 → 통째로 폴백
                unplaced += 1; continue
            }
            if hasUnresolvedDate(seg, dateHint: dateHint) {   // 월>12·불가능한 일·'월'만 등 미해석 날짜 → 폴백
                unplaced += 1; continue
            }
            if hasMultipleTimes(seg) {            // 시각이 2개 이상 남은 조각 → 제목 병합("수학 영어") 방지, 폴백
                unplaced += 1; continue
            }
            if AIKoreanDate.parse(seg, now: now, cal: cal).endRelativeDay != nil {
                unplaced += 1; continue           // "7/1부터 7/5까지" 기간 일정 → 모델(멀티데이 생성)로
            }

            let day = dateHint ?? carryDay ?? cal.startOfDay(for: now)
            let (rec, wds) = parseRecurrence(seg)
            if let t = time ?? pendingTime {
                var span = t
                var inferredPM = false, ambiguous = false
                if span.bare {   // 오전/오후 미표기 맨숫자 → 시간 맥락 모델로 해석(docs/AI_시간맥락모델.md)
                    let r = resolveBareHour(span.sH, title: title, day: day, context: context, cal: cal)
                    span.sH = r.hour; inferredPM = r.inferredPM; ambiguous = r.ambiguous
                }
                var ev = makeEvent(title: title, day: day, time: span, rec: rec, wds: wds, seg: seg, cal: cal)
                ev.inferredPM = inferredPM
                ev.amPmAmbiguous = ambiguous
                events.append(ev)
                pendingTime = nil
            } else if rec != .none || dateHint != nil {
                // 시각이 없어도 반복 표시(매주/매일/매월/매년)나 날짜가 있으면 종일 일정으로 생성
                // (시각은 미리보기 카드에서 조정). "매주 월요일 수학학원" 같은 입력을 모델에 넘기지 않음.
                events.append(makeAllDay(title: title, day: day, rec: rec, wds: wds, seg: seg, cal: cal))
            } else {
                unplaced += 1                     // 반복도·날짜도·시각도 없는 내용 → 붙일 수 없음
            }
        }

        if events.isEmpty || unplaced > 0 { return nil }
        return events
    }

    // MARK: - 시각

    struct TimeSpan {
        var sH: Int; var sM: Int; var eH: Int?; var eM: Int?
        var bare = false   // 오전/오후 미표기 맨숫자(1~12) — 해석은 parseEvents가 맥락으로
    }

    private enum Meridiem { case am, pm, none, noon, midnight }
    private struct HourTok { var h: Int; var m: Int; var mer: Meridiem; var night: Bool }

    /// 세그먼트에서 시각을 뽑는다.
    /// - "HH:MM"(콜론)은 24시간제 액면가. 단 오전/오후 표시가 있으면 반영.
    /// - "N시"(맨숫자, 표시 없음)는 낮 활동 가정: 1~7시는 오후(+12).
    /// - 오전/오후/저녁/밤/새벽/아침/정오/자정 표시 반영. 밤 12시=자정(00:00).
    /// - 범위: "9:00-18:00", "N시~M시", "N시부터 M시까지", "오후 2시-4시", "9~18시"(한쪽 시 생략).
    ///   한쪽에만 오전/오후가 있으면 다른 쪽이 상속. 둘 다 없으면 일관된 낮 활동 가정.
    /// "N시간"(기간)은 시각으로 보지 않음.
    static func fastTime(_ seg: String) -> TimeSpan? {
        let night = seg.contains("밤")
        // 1) 콜론 범위
        if let g = match(seg, #"(\d{1,2}):(\d{2})\s*[-~]\s*(\d{1,2}):(\d{2})"#),
           let sh = Int(g[1]), let sm = Int(g[2]), let eh = Int(g[3]), let em = Int(g[4]),
           sh < 24, sm < 60, eh < 24, em < 60 {
            let mer = colonMeridiem(seg)
            return TimeSpan(sH: applyMer(sh, mer, night: night), sM: sm,
                            eH: applyMer(eh, mer, night: night), eM: em)
        }
        // 2) 콜론 단일
        if let g = match(seg, #"(\d{1,2}):(\d{2})"#), let h = Int(g[1]), let m = Int(g[2]), h < 24, m < 60 {
            return TimeSpan(sH: applyMer(h, colonMeridiem(seg), night: night), sM: m, eH: nil, eM: nil)
        }
        // 3) 시(時) 범위 — 왼쪽 끝점은 구분자에 가장 가까운(마지막) 숫자를 취함(날짜 숫자 오인 방지)
        if let (a, b) = hourRangeParts(seg),
           let s = hourToken(a, bareOK: true, preferLast: true), let e = hourToken(b, bareOK: true) {
            let r = resolveRange(s, e)
            return TimeSpan(sH: r.sH, sM: r.sM, eH: r.eH, eM: r.eM)
        }
        // 4) 시(時) 단일
        if let t = hourToken(seg, bareOK: false) {
            if t.mer == .none, !t.night, (1...12).contains(t.h) {
                // 오전/오후 미표기 → 여기서 확정하지 않고 표시만(맥락 해석은 parseEvents에서)
                return TimeSpan(sH: t.h, sM: t.m, eH: nil, eM: nil, bare: true)
            }
            let (h, m) = resolve1(t)
            return TimeSpan(sH: h, sM: m, eH: nil, eM: nil)
        }
        return nil
    }

    /// 오전/오후 미표기 맨숫자 시각을 시간 맥락 모델로 해석(근거: docs/AI_시간맥락모델.md).
    /// 우선순위: 같은 제목의 기존 일정 패턴 > 새벽 배제(1~7시=오후) > 요일·방학·과목 맥락.
    /// ambiguous=true면 확정하지 않고 사용자 확인(오전/오후 선택)이 필요.
    static func resolveBareHour(_ h: Int, title: String, day: Date, context: AIParseContext,
                                cal: Calendar) -> (hour: Int, inferredPM: Bool, ambiguous: Bool) {
        guard (1...12).contains(h) else { return (h, false, false) }
        let pmH = h == 12 ? 12 : h + 12
        // 1) 학습된 패턴: 같은 제목의 기존 일정 시각과 일치하는 해석 우선
        if let hours = context.learnedHours[title] {
            if h != 12, hours.contains(pmH) { return (pmH, true, false) }
            if hours.contains(h) { return (h, false, false) }
        }
        if h == 12 { return (12, false, false) }               // 12시 = 낮(점심 평균 12:25)
        if (1...7).contains(h) { return (pmH, true, false) }   // 새벽 배제 — 낮 활동 가정
        // h 8~11
        let wd = cal.component(.weekday, from: day)
        if wd == 1 || wd == 7 || context.vacation == true {    // 주말·방학: 이른 시각 = 오전(주말 오전반·방학 특강)
            return (h, false, false)
        }
        if isAcademyLike(title) {                              // 평일 + 학원 컨텍스트
            if context.vacation == nil { return (h, false, true) }   // 방학 여부 불명 — 판정이 뒤집히는 구간 → 확인
            // 학기중: 오전 8~11시는 등교 시간이라 학원 불가. 8~9시는 저녁 수업(20~21시), 10~11시는 22시 시작이 조례 위반이라 확인.
            return (8...9).contains(h) ? (pmH, true, false) : (h, false, true)
        }
        return (h, false, false)                               // 병원·회의 등 일반 활동은 오전(표준 9~18시)
    }

    /// 학원/과목 컨텍스트인가 — 과목명 또는 학원류 접미어 포함.
    static func isAcademyLike(_ title: String) -> Bool {
        let t = title.replacingOccurrences(of: " ", with: "")
        let subjects = ["수학", "영어", "국어", "과학", "사회", "역사", "한국사", "물리", "화학",
                        "생물", "지구과학", "논술", "독서", "문법", "단어", "모의고사"]
        if subjects.contains(where: t.contains) { return true }
        for suf in ["학원", "과외", "특강", "보습", "교습", "수업", "스터디", "인강"] where t.contains(suf) { return true }
        return false
    }

    /// 콜론 시각용 오전/오후 판정(숫자에 붙은 표시만).
    private static func colonMeridiem(_ seg: String) -> Meridiem {
        if has(seg, #"(오후|저녁|밤)\s*\d"#) { return .pm }
        if has(seg, #"(오전|새벽|아침)\s*\d"#) { return .am }
        return .none
    }

    private static func applyMer(_ h: Int, _ mer: Meridiem, night: Bool) -> Int {
        switch mer {
        case .pm: if h == 12 { return night ? 0 : 12 }; return h < 12 ? h + 12 : h
        case .am: return h == 12 ? 0 : h
        case .noon: return 12
        case .midnight: return 0
        case .none: return h   // 콜론은 액면가(낮 활동 가정 안 함)
        }
    }

    /// 시(時) 토큰 파싱. bareOK면 '시' 없는 맨숫자도 허용(범위 끝점용). preferLast면 마지막 맨숫자.
    private static func hourToken(_ part: String, bareOK: Bool, preferLast: Bool = false) -> HourTok? {
        if part.contains("정오") { return HourTok(h: 12, m: 0, mer: .noon, night: false) }
        if part.contains("자정") { return HourTok(h: 0, m: 0, mer: .midnight, night: false) }
        let night = part.contains("밤")
        let mer: Meridiem = has(part, #"(오후|저녁|밤)\s*\d"#) ? .pm
                          : has(part, #"(오전|새벽|아침)\s*\d"#) ? .am : .none
        var h: Int
        let bare = allMatches(part, #"(?<!\d)\d{1,2}(?!\d)"#).compactMap { Int($0) }
        if let g = match(part, #"(\d{1,2})\s*시(?!간)"#), let v = Int(g[1]), v < 24 { h = v }
        else if bareOK, let v = (preferLast ? bare.last : bare.first), v < 24 { h = v }
        else { return nil }
        var m = 0
        if has(part, #"시\s*반(?![가-힣])"#) { m = 30 }   // '3시 반'=30분, 단 '3시 반포'의 반은 제외
        if let mm = match(part, #"시\s*(\d{1,2})\s*분"#), let v = Int(mm[1]), v < 60 { m = v }
        return HourTok(h: h, m: m, mer: mer, night: night)
    }

    private static func resolve1(_ t: HourTok) -> (Int, Int) {
        var h = t.h
        switch t.mer {
        case .noon: h = 12
        case .midnight: h = 0
        case .pm: h = (t.h == 12) ? (t.night ? 0 : 12) : (t.h < 12 ? t.h + 12 : t.h)
        case .am: h = (t.h == 12) ? 0 : t.h
        case .none: if (1...7).contains(t.h) { h = t.h + 12 }   // 맨숫자 낮 활동 가정
        }
        return (h, t.m)
    }

    private static func resolveRange(_ s: HourTok, _ e: HourTok) -> (sH: Int, sM: Int, eH: Int, eM: Int) {
        var sH: Int, eH: Int
        if s.mer == .none && e.mer == .none {
            // 둘 다 표시 없음 → 일관 낮 활동 가정
            let sr = s.h, er = e.h
            if sr <= 12 && er <= 12 && sr < er {
                if sr <= 7 { sH = sr + 12; eH = er + 12 } else { sH = sr; eH = er }
            } else if sr <= 12 && er <= 12 && sr > er {
                sH = sr; eH = er + 12          // 정오를 넘김(오전→오후)
            } else {
                sH = sr; eH = er               // 한쪽이 이미 13~23(예: 9~18시)
            }
        } else {
            // 한쪽만 표시면 다른 쪽이 상속
            var sMer = s.mer, eMer = e.mer
            if sMer == .none { sMer = eMer }
            if eMer == .none { eMer = sMer }
            sH = resolve1(HourTok(h: s.h, m: s.m, mer: sMer, night: s.night)).0
            eH = resolve1(HourTok(h: e.h, m: e.m, mer: eMer, night: e.night)).0
        }
        var eM = e.m
        if eH <= sH { eH = min(23, sH + 1); eM = s.m }   // 종료 ≤ 시작 보정
        return (sH, s.m, eH, eM)
    }

    /// 시(時) 범위를 앞/뒤 조각으로. 구분자: '~', '부터', 또는 (숫자/시)-(숫자) 하이픈.
    private static func hourRangeParts(_ seg: String) -> (String, String)? {
        guard seg.contains("시") else { return nil }
        let sep: Range<String.Index>?
        if let r = seg.range(of: "~") { sep = r }
        else if let r = seg.range(of: "부터") { sep = r }
        else if let r = seg.range(of: #"(?<=[0-9시])\s*-\s*(?=\d)"#, options: .regularExpression) { sep = r }
        else { sep = nil }
        guard let r = sep else { return nil }
        let a = String(seg[..<r.lowerBound]), b = String(seg[r.upperBound...])
        return (a.contains("시") || b.contains("시")) ? (a, b) : nil
    }

    // MARK: - 날짜

    private static func detectDate(_ seg: String, now: Date, cal: Calendar, yearShift: Int) -> Date? {
        if let (m, d) = absoluteMonthDay(seg), let date = makeAbsolute(m, d, yearShift: yearShift, now: now, cal: cal) {
            return date
        }
        if let rd = AIKoreanDate.parse(seg, now: now, cal: cal).relativeDay {
            return cal.date(byAdding: .day, value: rd, to: cal.startOfDay(for: now))
        }
        return nil
    }

    private static func absoluteMonthDay(_ seg: String) -> (Int, Int)? {
        if let g = match(seg, #"(\d{1,2})\s*월\s*(\d{1,2})\s*일"#), let m = Int(g[1]), let d = Int(g[2]),
           (1...12).contains(m), (1...31).contains(d) { return (m, d) }
        if let g = match(seg, #"(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)"#), let m = Int(g[1]), let d = Int(g[2]),
           (1...12).contains(m), (1...31).contains(d) { return (m, d) }
        return nil
    }

    private static func makeAbsolute(_ m: Int, _ d: Int, yearShift: Int, now: Date, cal: Calendar) -> Date? {
        var c = cal.dateComponents([.year], from: cal.startOfDay(for: now))
        c.year = (c.year ?? 0) + yearShift; c.month = m; c.day = d
        return cal.date(from: c)
    }

    /// (m, d)가 실재하는 달/일인가(2월 30일·4월 31일·13월 등 거부). 2월은 윤년 허용 위해 29까지.
    private static func validMonthDay(_ m: Int, _ d: Int) -> Bool {
        guard (1...12).contains(m) else { return false }
        let maxDay = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
        return (1...maxDay).contains(d)
    }

    /// 절대 날짜 구문이 있으나 해석에 실패했는가(월>12, 실재 않는 일, '일' 없는 '월만')?
    /// true면 '미해석 날짜' → parseEvents가 통째로 모델에 폴백(오늘로 억지 생성·엉뚱한 날 롤오버 방지).
    private static func hasUnresolvedDate(_ seg: String, dateHint: Date?) -> Bool {
        if let g = match(seg, #"(\d{1,2})\s*월\s*(\d{1,2})\s*일"#), let m = Int(g[1]), let d = Int(g[2]) {
            return validMonthDay(m, d) ? (dateHint == nil) : true
        }
        if let g = match(seg, #"(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)"#), let m = Int(g[1]), let d = Int(g[2]) {
            return validMonthDay(m, d) ? (dateHint == nil) : true
        }
        if has(seg, #"(?<!\d)\d{1,2}\s*월(?!\s*\d)"#) && dateHint == nil { return true }   // '8월'처럼 월만 있고 미해석
        return false
    }

    /// 배치의 절대 날짜 연도 이동량. 오늘 이후까지 걸치면 0(올해). 전부 과거면: 최근(≤120일) 다일 배치는 0,
    /// 단일 과거·먼 과거는 +1(다가오는 것).
    private static func absoluteYearShift(_ segs: [String], now: Date, cal: Calendar) -> Int {
        let today = cal.startOfDay(for: now)
        let dates = segs.compactMap { seg -> Date? in
            guard let (m, d) = absoluteMonthDay(seg) else { return nil }
            var c = cal.dateComponents([.year], from: today); c.month = m; c.day = d
            return cal.date(from: c)
        }
        guard let maxDate = dates.max() else { return 0 }
        if maxDate >= today { return 0 }
        let gap = cal.dateComponents([.day], from: maxDate, to: today).day ?? 0
        if dates.count >= 2 && gap <= 120 { return 0 }
        return 1
    }

    // MARK: - 이벤트 조립

    private static func makeEvent(title: String, day: Date, time: TimeSpan, rec: Recurrence, wds: Set<Int>,
                                  seg: String, cal: Calendar) -> ParsedEvent {
        let start = cal.date(bySettingHour: min(23, max(0, time.sH)), minute: clamp(time.sM), second: 0, of: day) ?? day
        let end: Date
        if let eh = time.eH, (0...23).contains(eh) {
            var e = cal.date(bySettingHour: eh, minute: clamp(time.eM ?? 0), second: 0, of: day) ?? start
            if e <= start { e = start.addingTimeInterval(3600) }
            end = e
        } else {
            end = start.addingTimeInterval(3600)
        }
        return ParsedEvent(title: title, start: start, end: end, location: extractLocation(seg),
                           action: .create, recurrence: rec, weekdays: wds)
    }

    /// 시각 없는(종일) 일정 — 그 날 00:00부터 다음날 00:00까지(앱의 멀티데이 표현과 동일).
    private static func makeAllDay(title: String, day: Date, rec: Recurrence, wds: Set<Int>,
                                  seg: String, cal: Calendar) -> ParsedEvent {
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return ParsedEvent(title: title, start: start, end: end, location: extractLocation(seg),
                           action: .create, recurrence: rec, weekdays: wds)
    }

    private static func clamp(_ m: Int) -> Int { max(0, min(59, m)) }

    // MARK: - 반복

    private static func parseRecurrence(_ seg: String) -> (Recurrence, Set<Int>) {
        // "매주마다/매일마다" 같은 군더더기 '~마다'를 표준형으로 정규화
        let s = seg.replacingOccurrences(of: #"(매주|매일|매달|매월|매년|매해)\s*마다"#,
                                         with: "$1", options: .regularExpression)
        if has(s, #"격주|2주마다|이주마다"#) { return (.biweekly, []) }
        if has(s, #"주말마다|매\s*주말"#) { return (.weekly, [1, 7]) }
        if has(s, #"매주(?![가-힣])|주마다"#) { return (.weekly, weeklyDays(s)) }
        if has(s, #"매일(?![가-힣])|날마다"#) { return (.daily, []) }
        if has(s, #"매달(?![가-힣])|매월(?![가-힣])|달마다"#) { return (.monthly, []) }
        if has(s, #"매년(?![가-힣])|매해(?![가-힣])|해마다"#) { return (.yearly, []) }
        let map: [Character: Int] = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7]
        // "<요일>마다"("월요일마다"·"월수금마다") — '매주' 없이도 매주 반복
        if let g = match(s, #"(?<![가-힣0-9])([월화수목금토일](?:\s*[월화수목금토일])*)\s*(?:요일)?\s*마다(?![가-힣])"#) {
            let days = Set(g[1].compactMap { map[$0] })
            if !days.isEmpty { return (.weekly, days) }
        }
        // '매주' 없이 요일 뭉치만("월수금 수학") — 요일 2개 이상 나열은 매주 반복으로 본다(학원 관행)
        if let g = match(s, #"(?<![가-힣0-9])([월화수목금토일]{2,7})(?:\s*요일)?(?![가-힣])"#) {
            let days = Set(g[1].compactMap { map[$0] })
            if days.count >= 2 { return (.weekly, days) }
        }
        return (.none, [])
    }

    /// "매주 월수금" / "매주 화목" / "매주 화요일" → 요일 집합(1=일…7=토).
    private static func weeklyDays(_ seg: String) -> Set<Int> {
        let map: [Character: Int] = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7]
        if seg.contains("주말") { return [1, 7] }                        // 주말 = 토·일
        if let g = match(seg, #"매주\s*([월화수목금토일](?:\s*[월화수목금토일])+)(?:\s*(?:요일|마다))*(?![가-힣])"#) {
            return Set(g[1].compactMap { map[$0] })   // "매주 월수금"·"매주 월 수 금"·"매주 월수금마다" 모두
        }
        let full: [(String, Int)] = [("월요일", 2), ("화요일", 3), ("수요일", 4),
                                     ("목요일", 5), ("금요일", 6), ("토요일", 7), ("일요일", 1)]
        let byFull = Set(full.filter { seg.contains($0.0) }.map { $0.1 })
        if !byFull.isEmpty { return byFull }
        // '매주 월'처럼 단일 요일 글자가 '매주' 바로 뒤 독립 토큰(뒤에 한글 없음)일 때만 — '매주 수학'의 '수' 오인 방지.
        if let g = match(seg, #"매주\s*([월화수목금토일])(?![가-힣])"#), let c = g[1].first, let wd = map[c] {
            return [wd]
        }
        return []
    }

    // MARK: - 제목 추출

    /// 날짜·시각·반복·장소 토큰을 떼어내고 핵심(제목)만 남긴다.
    /// 오전/오후 등 시간대 표시는 **숫자에 붙어 있을 때만** 제거(밤샘/오전반/점심 회식 등 보존).
    static func extractTitle(_ seg: String) -> String {
        var s = seg

        // @장소(숫자 없어 안전)
        s = removeRegex(s, #"@\s*[가-힣A-Za-z0-9]+"#)

        // 시간대 표시(숫자 인접) + 정오/자정 — 장소구보다 먼저(장소구가 '2시'를 먼저 먹지 않게)
        s = removeRegex(s, #"(오전|오후|새벽|아침|점심|저녁|밤|낮)\s*(?=\d)"#)
        s = removeWords(s, ["정오", "자정"])

        // 시각(경/쯤/무렵/반은 '시' 뒤일 때만 함께 제거 → '경기'의 '경' 등 보존)
        for p in [
            #"(\d{1,2}):(\d{2})\s*[-~]\s*(\d{1,2}):(\d{2})"#,
            #"\d{1,2}\s*:\s*\d{2}"#,
            #"\d{1,2}\s*시\s*\d{1,2}\s*분"#,
            #"\d{1,2}\s*시\s*[-~]\s*\d{1,2}\s*시"#,
            #"\d{1,2}\s*[~]\s*\d{1,2}\s*시"#,
            #"\d{1,2}\s*시(?:\s*반(?![가-힣]))?(?:경|쯤|무렵)?(?!간)"#,   // '반'은 뒤에 한글 없을 때만, '경/쯤/무렵'은 시에 붙을 때만(경기·반포 보존)
            #"\d{1,2}\s*[~]\s*\d{1,2}"#,
        ] { s = removeRegex(s, p) }
        s = removeWords(s, ["부터", "까지"])

        // 장소구("X에서") — 시각을 뗀 뒤라 '3시 회의에서'의 시각을 먹지 않음
        s = removeRegex(s, #"[가-힣A-Za-z0-9]+(?:\s[가-힣A-Za-z0-9]+)?\s*에서"#)

        // 반복(요일 뭉치는 '매주/격주'에 붙은 것만) — 날짜어보다 먼저
        s = removeRegex(s, #"(매주|매일|매달|매월|매년|매해)\s*마다"#)   // "매주마다" 군더더기형 통째로
        s = removeRegex(s, #"매\s*주말"#)                       // '매주말' → 주말 반복(통째로 먼저 제거)
        s = removeRegex(s, #"(매주|격주|주마다)\s*[월화수목금토일](?:\s*[월화수목금토일])*(?:\s*요일)?(?:\s*마다)?(?![가-힣])"#)   // 요일 뭉치도 단어 경계 요구('매주 수학'의 '수' 보존), "월 수 금" 띄어쓰기·'마다' 허용
        s = removeRegex(s, #"(?<![가-힣0-9])[월화수목금토일](?:\s*[월화수목금토일])*\s*(?:요일)?\s*마다(?![가-힣])"#)   // "월요일마다"·"월수금마다"('생일마다'는 경계로 보존)
        s = removeWords(s, ["주말마다", "매일매일", "격주", "2주마다", "이주마다",
                            "날마다", "주마다", "달마다", "해마다"])
        for p in [#"매주(?![가-힣])"#, #"매일(?![가-힣])"#, #"매달(?![가-힣])"#,
                  #"매월(?![가-힣])"#, #"매년(?![가-힣])"#, #"매해(?![가-힣])"#] { s = removeRegex(s, p) }

        // 날짜(절대)
        for p in [
            #"(\d{1,2})\s*월\s*(\d{1,2})\s*일"#,
            #"(?<!\d)\d{1,2}\s*/\s*\d{1,2}(?!\d)"#,
            #"\d{1,2}\s*(일|주|주일|달|개월)\s*(후|뒤|전|있다가|지나)"#,
            #"(열흘|아흐레|여드레|이레|엿새|닷새|나흘|사흘|이틀)\s*(후|뒤|전|있다가|지나)"#,
            #"\d{1,2}\s*월"#,
            #"\d{1,2}\s*일(?!간)"#,
        ] { s = removeRegex(s, p) }

        // 날짜(상대·요일) — 한글 단어 경계에서만 제거('주말농장'의 '주말', '내일신문'의 '내일'을 먹지 않음)
        s = removeStandaloneWords(s, [
            "내일모레", "그글피", "그저께", "다다음주", "다다음 주", "다다음달", "다다음 달",
            "다음주", "다음 주", "이번주", "이번 주", "다음달", "다음 달", "이번달", "이번 달",
            "담주", "담 주", "담달", "담 달", "금주", "주말", "월말", "말일",
            "오늘", "내일", "모레", "글피", "어제", "그제", "이따가", "이따", "곧",
            "열흘", "아흐레", "여드레", "이레", "엿새", "닷새", "나흘", "사흘", "이틀",
            "월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일",
        ])
        // 요일 뭉치("월수금 수학")와 한 글자 요일("금 5시 수학") — 홀로 선 토큰만('수학'의 수, '8월'의 월은 보존)
        s = removeRegex(s, #"(?<![가-힣0-9])[월화수목금토일]{2,7}(?:\s*요일)?(?![가-힣])"#)
        s = removeRegex(s, #"(?<![가-힣0-9])[월화수목금토일](?![가-힣])"#)

        // 요청 어미 — "추가해줘/넣어 줘/등록해주세요/잡아줄래" 같은 명령 꼬리는 제목이 아님.
        // 단계마다 비면 직전 값으로 되돌리고 멈춤 → "일정 추가해줘"는 '일정'까지만 남는다.
        for p in [
            #"(?:을|를)?\s*(?:추가|등록|입력|저장|기록|생성)?\s*해\s*[주줘줄][가-힣]*\s*$"#,   // …해줘/해 주세요/해줄래
            #"(?:을|를)?\s*(?:넣|잡|적)\s*[아어]\s*[주줘줄][가-힣]*\s*$"#,                      // 넣어줘/잡아 줘/적어줄래
            #"(?:을|를)?\s*만들\s*어\s*[주줘줄][가-힣]*\s*$"#,                                   // 만들어줘
            #"(?:을|를)?\s*(?:추가|등록)\s*$"#,                                                  // 맨몸 '추가/등록' 꼬리
            #"(?:일정|스케줄)\s*(?:으로|로)?\s*$"#,                                              // '축구 일정으로' → '축구'
        ] {
            let t = removeRegex(s, p)
            if t.trimmingCharacters(in: .whitespaces).isEmpty { break }
            s = t
        }

        // 잔여 정리
        s = s.replacingOccurrences(of: "~", with: " ")
        s = removeRegex(s, #"[-–—]"#)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return stripEdgeParticles(s)
    }

    private static func stripEdgeParticles(_ input: String) -> String {
        var s = input
        let lead = ["에서", "에", "부터", "까지", "요일", "은", "는", "이", "가", "을", "를", "로", "으로", "및", "그리고"]
        var changed = true
        while changed {
            changed = false
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            for p in lead where s.hasPrefix(p + " ") || s == p {
                s.removeFirst(p.count); changed = true
            }
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—~"))
    }

    /// 제목에 미해석 날짜·시각 숫자가 남아 있으면 true(→ 통째로 모델 폴백).
    /// 고립된 1~2자리 숫자(예: '7-1'이 '7 1'로 남음)나 남은 시각 표기.
    private static func hasParseResidue(_ title: String) -> Bool {
        if has(title, #"(?<![가-힣A-Za-z0-9])\d{1,2}(?![가-힣A-Za-z0-9])"#) { return true }
        if has(title, #"\d{1,2}\s*시(?!간)"#) { return true }
        if has(title, #"\d{1,2}\s*:\s*\d{2}"#) { return true }
        return false
    }

    // MARK: - 장소

    static func extractLocation(_ seg: String) -> String {
        let deny: Set<String> = ["회의", "수업", "미팅", "모임", "파티", "행사", "발표", "세미나", "시험",
                                 "점심", "저녁", "아침", "오전", "오후"]
        let dateWords: Set<String> = ["오늘", "내일", "모레", "글피", "어제", "그제", "그저께",
                                      "다음주", "이번주", "다다음주", "담주", "주말", "월말",
                                      "월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"]
        if let g = match(seg, #"([가-힣A-Za-z0-9]+(?:\s[가-힣A-Za-z0-9]+)?)\s*에서"#) {
            let toks = g[1].split(separator: " ").map(String.init).filter { tok in
                if dateWords.contains(tok) { return false }              // 날짜·요일어 제외
                if has(tok, #"^\d"#) { return false }                    // 숫자로 시작(시각/날짜 잔여)
                if has(tok, #"\d\s*[시분일월]$"#) { return false }        // '3시'·'30분'·'10일'·'8월'만 제외(수원'시'는 보존)
                return true
            }
            let place = toks.joined(separator: " ")
            if !place.isEmpty, !deny.contains(place),
               place.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
                return place
            }
        }
        if let g = match(seg, #"@\s*([가-힣A-Za-z0-9]+)"#) { return g[1] }
        return ""
    }

    // MARK: - 의도 게이트

    /// '일정 생성'이 아닌 의도(질문/수정/삭제/외형/후속)면 true → 모델에 맡긴다.
    /// 이름('수정')·스포츠('조정')·영화('다크나이트')·행사('화이트데이') 오탐을 줄이려
    /// 외형은 '모드/테마'와 함께일 때만, 수정/조정은 동사형일 때만 인식.
    static func isNonCreateIntent(_ text: String) -> Bool {
        // 원문에서 검사(공백을 지우지 않음) — '…까지 워크숍'의 '까지'+'워'가 붙어 삭제어 '지워'로
        // 오검출되던, 단어 경계를 넘는 부분 문자열 매칭을 막는다.
        let t = text
        if t.contains("?") || t.contains("？") { return true }
        for w in ["뭐야", "뭐가", "뭐있", "뭐먹", "무엇", "언제", "몇시", "며칠", "몇개",
                  "알려줘", "알려줄", "알려주", "궁금", "있어", "있나", "있는지", "없어"] where t.contains(w) { return true }
        for w in ["급식", "식단"] where t.contains(w) { return true }
        if hasDeleteCue(t) { return true }
        if hasUpdateCue(t) { return true }
        if (t.contains("다크") || t.contains("라이트") || t.contains("화이트") || t.contains("야간") || t.contains("주간"))
            && (t.contains("모드") || t.contains("테마")) { return true }
        for w in ["그거말고", "그건말고", "그게아니", "다른거로", "다른걸로"] where t.contains(w) { return true }
        return false
    }

    /// 삭제 의도 단어가 실제로 들어 있는가 — 모델이 수정 요청을 삭제로 오해했을 때 걸러내는 안전장치로도 사용.
    static func hasDeleteCue(_ text: String) -> Bool {
        for w in ["취소", "삭제", "지워", "지울", "지운", "없애", "없앨", "없던", "캔슬",
                  "빼줘", "빼주", "빼자", "빼버려", "빼고싶"] where text.contains(w) { return true }
        let lower = text.lowercased()
        for w in ["delete", "remove", "cancel"] where lower.contains(w) { return true }
        return false
    }

    /// 수정(시간·날짜 변경) 의도 단어가 들어 있는가.
    static func hasUpdateCue(_ text: String) -> Bool {
        for w in ["옮겨", "옮길", "옮기", "미뤄", "미룰", "미루", "당겨", "당길", "앞당", "늦춰", "늦출", "늦추",
                  "변경", "조정해", "조정하", "조정할", "수정해", "수정하", "수정할",
                  "바꿔", "바꾸고", "바꿀"] where text.contains(w) { return true }
        return false
    }

    private static func isNoiseHeader(_ title: String) -> Bool {
        let noise: Set<String> = [
            "날짜", "시간", "시각", "내용", "일정", "제목", "장소", "위치", "비고", "구분", "순서", "요일",
            "전체", "전체일정", "전체 일정", "스케줄", "타임테이블", "프로그램",
            "date", "time", "content", "title", "location", "day", "event", "schedule", "no",
        ]
        let key = title.replacingOccurrences(of: " ", with: "").lowercased()
        if noise.contains(title) || noise.contains(key) { return true }
        // 다열 헤더("날짜⇥시간⇥내용"이 탭→공백으로 한 세그먼트가 된 경우): 모든 토큰이 noise면 머리글.
        let toks = title.split(separator: " ").map { String($0).lowercased() }
        return toks.count >= 2 && toks.allSatisfy { noise.contains($0) }
    }

    // MARK: - 세그먼트 분리

    static func segment(_ text: String) -> [String] {
        var lines: [String] = []
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            var line = String(rawLine).replacingOccurrences(of: "\t", with: " ")
            for sep in ["그리고나서", "그리고는", "그리고", "그 다음에", "그다음에", "그 담에", "그담에"] {
                line = line.replacingOccurrences(of: sep, with: ",")
            }
            for part in line.split(whereSeparator: { $0 == "," || $0 == "，" }) {
                let s = part.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { lines.append(contentsOf: splitChainedSchedules(s)) }
            }
        }
        return lines
    }

    /// 구분자 없이 한 줄에 이어 쓴 여러 일정("오늘 8시 수학 금요일 5시 수학")을 날짜 토큰 앞에서 분할.
    /// 왼쪽 조각이 이미 시각을 가진 경우에만 자름 → "소풍 내일 3시"처럼 날짜가 뒤에 오는 단일 일정은 보존.
    private static func splitChainedSchedules(_ line: String) -> [String] {
        let datePat = #"(?<=\s)(?:오늘|내일모레|내일|모레|글피|어제|다다음\s*주|다음\s*주|이번\s*주|담주|다음\s*달|이번\s*달|[월화수목금토일]요일|[월화수목금토일](?![가-힣])|\d{1,2}\s*월\s*\d{1,2}\s*일|\d{1,2}\s*/\s*\d{1,2})"#
        guard let re = try? NSRegularExpression(pattern: datePat) else { return [line] }
        let ns = line as NSString
        var pieces: [String] = []
        var pieceStart = 0
        for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let cur = ns.substring(with: NSRange(location: pieceStart, length: m.range.location - pieceStart))
            if hasTimeToken(cur) {   // 왼쪽에 이미 시각이 있으면 여기서 새 일정 시작
                pieces.append(cur.trimmingCharacters(in: .whitespaces))
                pieceStart = m.range.location
            }
        }
        let last = ns.substring(from: pieceStart).trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { pieces.append(last) }
        return pieces.isEmpty ? [line] : pieces
    }

    private static func hasTimeToken(_ s: String) -> Bool {
        has(s, #"(?<!\d)\d{1,2}\s*시(?!간)"#) || has(s, #"(?<!\d)\d{1,2}\s*:\s*\d{2}"#)
    }

    /// 한 세그먼트에 시각 표현이 2개 이상 남아 있는가(범위 제외).
    /// true면 제목이 "수학 영어"처럼 합쳐질 상황 → 통째로 모델 폴백.
    private static func hasMultipleTimes(_ seg: String) -> Bool {
        if hourRangeParts(seg) != nil { return false }                       // "5~7시"류 범위는 정상
        if has(seg, #"\d{1,2}:\d{2}\s*[-~]\s*\d{1,2}:\d{2}"#) { return false }   // "9:00-18:00"
        let n = allMatches(seg, #"(?<!\d)\d{1,2}\s*시(?!간)"#).count
              + allMatches(seg, #"(?<!\d)\d{1,2}\s*:\s*\d{2}"#).count
        return n >= 2
    }

    // MARK: - 정규식 헬퍼

    private static func match(_ text: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func has(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// 패턴에 맞는 모든 부분 문자열.
    private static func allMatches(_ text: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func removeRegex(_ text: String, _ pattern: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = NSMutableString(string: text)
        re.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: " ")
        return ns as String
    }

    private static func removeWords(_ text: String, _ words: [String]) -> String {
        var s = text
        for w in words { s = s.replacingOccurrences(of: w, with: " ") }
        return s
    }

    /// removeWords와 같지만 한글 단어 경계에서만 제거('주말농장'의 '주말', '수원'의 앞뒤를 먹지 않음).
    private static func removeStandaloneWords(_ text: String, _ words: [String]) -> String {
        var s = text
        for w in words {
            s = removeRegex(s, #"(?<![가-힣])"# + NSRegularExpression.escapedPattern(for: w) + #"(?![가-힣])"#)
        }
        return s
    }

    // MARK: - 장소 검증(MapKit)

    private static func validatePlace(_ query: String) async -> String {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return "" }
        let generic = ["집", "우리집", "집앞", "학교", "회사", "교실", "도서관", "동네", "근처", "온라인", "줌", "zoom"]
        if generic.contains(q) { return q }
        #if canImport(MapKit)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.pointOfInterest, .address]
        if let resp = try? await MKLocalSearch(request: request).start(), let item = resp.mapItems.first {
            return item.name ?? q
        }
        #endif
        return q
    }
}
