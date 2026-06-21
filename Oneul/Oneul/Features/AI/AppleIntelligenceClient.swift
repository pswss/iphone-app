import Foundation
import MapKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 애플 인텔리전스(온디바이스, iOS 26+) 기반 앱 비서. 키 불필요.
/// 모델은 '의미 슬롯'만 채우고(날짜/시각 ISO 생성 금지), 실제 계산은 Swift(AIDateResolver)가 한다.
struct AppleIntelligenceClient: ScheduleAI {
    func generateSchedule(from text: String, now: Date, existing: [ExistingEvent]) async throws -> AIResult {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return try await AppleAI.generate(from: text, now: now, existing: existing)
        }
        #endif
        throw AppleIntelligenceUnavailable(
            reason: "이 기기에서는 애플 인텔리전스를 쓸 수 없어요. 다른 AI를 선택하세요.")
    }

    /// 첫 응답 지연을 줄이기 위해 모델 세션을 미리 데움.
    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) { AppleAI.prewarm() }
        #endif
    }

    func validate() async -> AIValidation {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return AppleAI.availability()
        }
        #endif
        return .failed("iOS 26 이상 + 애플 인텔리전스 지원 기기 필요")
    }
}

struct AppleIntelligenceUnavailable: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
enum AppleAI {
    // MARK: 의미 슬롯 스키마 (모델은 슬롯만 채운다 — 날짜/시각 계산은 Swift가)
    @Generable
    struct GenResponse {
        @Guide(description: "사용자 말에서 뽑아낸 명령 목록. 단순 단어·잡담이면 빈 배열")
        var commands: [GenCommand]
    }

    @Generable
    struct GenCommand {
        @Guide(description: "의도 하나: scheduleCreate(새 일정), scheduleUpdate(기존 일정 시간/내용 변경), scheduleDelete(기존 일정 취소/삭제), mealQuery(급식 질문), scheduleQuery(내 일정·시험이 언제/뭐 있는지 질문), setAppearance(다크/라이트/시스템 전환), unknown(그 외·잡담)")
        var intent: String

        @Guide(description: "상대 날짜: 오늘=0, 내일=1, 모레=2, 어제=-1. 요일·절대날짜를 쓰면 0")
        var relativeDay: Int
        @Guide(description: "요일을 말하면 mon,tue,wed,thu,fri,sat,sun 중 하나. 요일 안 쓰면 빈 문자열")
        var weekday: String
        @Guide(description: "요일과 함께: 이번주=0, 다음주=1, 다다음주=2. 요일 없으면 0")
        var weekOffset: Int
        @Guide(description: "절대 월(1-12). 며칠을 콕 집어 말할 때만. 아니면 0")
        var month: Int
        @Guide(description: "절대 일(1-31). 아니면 0")
        var day: Int

        @Guide(description: "시작 시(24시간제 0-23). 오후 5시=17, 저녁 7시=19, 밤 9시=21. 시각 안 말하면 -1")
        var startHour: Int
        @Guide(description: "시작 분(0-59). 안 말하면 0")
        var startMinute: Int
        @Guide(description: "종료 시(24시간제 0-23). 'N~M시'의 M. 없으면 -1")
        var endHour: Int
        @Guide(description: "종료 분(0-59). 없으면 0")
        var endMinute: Int

        @Guide(description: "반복: none,daily,weekly,biweekly,monthly,yearly. 반복 아니면 none")
        var recurrence: String
        @Guide(description: "매주 특정 요일 반복이면 쉼표로(예 'mon,wed,fri'). 아니면 빈 문자열")
        var recurrenceWeekdays: String

        @Guide(description: "제목(시간·날짜 빼고 핵심만, 예 '내일 9시 회의'→'회의'). 일정이 아니면 빈 문자열")
        var title: String
        @Guide(description: "장소. 없으면 빈 문자열")
        var location: String

        @Guide(description: "수정/삭제 대상 기존 일정 번호([1],[2]…). 새 일정·그 외면 0")
        var targetIndex: Int
        @Guide(description: "'전부·싹다·모두'처럼 같은 제목 일괄 삭제면 true")
        var bulk: Bool

        @Guide(description: "setAppearance면 system/light/dark. 아니면 빈 문자열")
        var appearance: String
        @Guide(description: "scheduleQuery면 day(특정 날 일정)/week(한 주 일정)/exam(시험 언제). 아니면 빈 문자열")
        var queryKind: String
    }

    // 정적 instructions로 세션 1개 재사용(동적 컨텍스트는 프롬프트로 → prewarm 가능).
    private static let instructions = """
    너는 한국어 개인 비서다. 사용자의 말을 이해해 commands 목록으로 바꾼다.
    가장 중요: 절대 ISO 날짜/타임스탬프를 만들지 마라. 날짜·시각 계산은 앱이 한다. 너는 아래 '슬롯'만 채운다.

    [intent 고르기] 명령마다 하나. 여러 일을 말하면 commands에 여러 개(쉼표·'그리고'로 나뉜 일정은 각각).
    - scheduleCreate: 새 일정/약속/할 일 추가.
    - scheduleUpdate: 기존 일정의 시간·내용 변경(옮겨/바꿔/변경).
    - scheduleDelete: 기존 일정 취소/삭제/지워.
    - mealQuery: 급식/식단 질문.
    - scheduleQuery: 내 일정이나 시험이 언제/뭐가 있는지 묻는 질문.
    - setAppearance: 다크/라이트/시스템(자동) 모드로 바꿔달라는 요청.
    - unknown: 위 어디에도 안 맞거나 단순 단어·이름·잡담(예: "아리랑", "안녕").

    [날짜 슬롯] 말 안 한 건 기본값.
    - relativeDay: 오늘=0, 내일=1, 모레=2, 어제=-1.
    - 요일을 말하면 weekday(mon..sun) + weekOffset(이번주=0, 다음주=1, 다다음주=2). 요일 안 쓰면 weekday="".
    - 며칠을 콕 집으면 month·day(예: 12월 25일 → month=12, day=25).

    [시각 슬롯] 24시간제로 변환.
    - startHour 0-23. 오후 5시=17, 저녁 7시=19, 밤 9시=21. 시각을 안 말하면 startHour=-1.
    - "N~M시"/"N시부터 M시까지"는 startHour=N, endHour=M. 오전/오후 표시가 없고 학원·수업·약속 등 낮 활동이면 오후(13시 이후)로 본다. 예: "1~5시 수학학원" → startHour=13, endHour=17.
    - 종료를 안 말하면 endHour=-1.

    [반복] 매주/매일 등 반복이면 recurrence 설정. "매주 월수금" → recurrence=weekly, recurrenceWeekdays="mon,wed,fri". 반복 아니면 recurrence=none, recurrenceWeekdays="".

    [수정/삭제 대상] 프롬프트의 기존 일정 목록에서 [번호]를 targetIndex에 넣는다. "전부/싹다/모두" 삭제면 bulk=true. 새 일정이면 targetIndex=0, bulk=false.

    [기타]
    - "7/1부터 7/5까지", "A부터 B까지" 같은 여러 날 지속되는 기간 일정도 intent=scheduleCreate, title은 날짜 빼고 핵심만. (날짜 범위 계산은 앱이 한다.)
    - title은 시간·날짜를 빼고 핵심만 남긴다. 장소 없으면 location="".
    - setAppearance면 appearance=system/light/dark, 아니면 "".
    - scheduleQuery면 queryKind=day/week/exam, 아니면 "".
    """

    // 매 요청마다 새 세션(누적 컨텍스트 초과 방지). 1개 미리 데워 첫 응답 지연만 줄인다.
    private static var _primed: LanguageModelSession?
    // 직전 사용자 요청 — '그거/그럼/거기' 같은 후속 질문의 맥락으로만 사용(세션은 누적 안 함).
    private static var lastRequest: String?
    // 직전 삭제 맥락 — "아니 그거 말고"라고 하면 다른 후보를 제시하기 위해.
    private static var lastDeleteKeyword: String?
    private static var lastDeleteChosen: UUID?

    static func prewarm() {
        guard _primed == nil else { return }   // 이미 데웠으면 즉시 반환
        Task.detached(priority: .utility) {    // 모델 워밍업을 메인 스레드 밖 낮은 우선순위로(첫 타이핑 렉↓)
            guard case .available = SystemLanguageModel.default.availability else { return }
            let s = LanguageModelSession(instructions: instructions)
            _primed = s
            s.prewarm()
        }
    }

    static func availability() -> AIValidation {
        switch SystemLanguageModel.default.availability {
        case .available: return .ok
        case .unavailable(let reason): return .failed(describe(reason))
        }
    }

    static func generate(from text: String, now: Date, existing: [ExistingEvent]) async throws -> AIResult {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AppleIntelligenceUnavailable(
                reason: "애플 인텔리전스를 사용할 수 없어요 (설정에서 켜야 할 수 있어요).")
        }

        // "아니 그거 말고" 류 후속 → 모델 호출 없이 직전 삭제 맥락에서 다른 후보 제시
        if isRejectionFollowup(text), let kw = lastDeleteKeyword {
            let cands = existing.filter {
                !$0.title.isEmpty && ($0.title.contains(kw) || kw.contains($0.title)) && $0.id != lastDeleteChosen
            }
            if !cands.isEmpty {
                lastRequest = text
                return AIResult(events: [], actions: [.clarifyDelete(
                    candidates: cands.map { DeleteCandidate(id: $0.id, title: $0.title, start: $0.start) },
                    prompt: "그럼 이 중에 어떤 걸 삭제할까요?")])
            }
        }

        let isoNow = ISO8601DateFormatter().string(from: now)
        var prompt = "현재 시각: \(isoNow) (\(TimeZone.current.identifier)).\n"
        if let last = lastRequest {
            prompt += "직전 질문: \(last)\n(이번 요청에 '그거/거기/그날/그럼/그때' 같은 지시어가 있으면 직전 질문을 이어서 해석. 직전 질문 자체를 다시 처리하지는 말 것.)\n"
        }
        if !existing.isEmpty {
            prompt += "기존 일정 목록(수정/삭제 대상):\n"
            for (i, e) in existing.enumerated() {
                prompt += "[\(i + 1)] \(shortDate(e.start)) \(e.title)\n"
            }
        }
        prompt += "\n요청: \(text)"

        let session = _primed ?? LanguageModelSession(instructions: instructions)
        _primed = nil
        let response = try await session.respond(to: prompt, generating: GenResponse.self)
        prewarm()   // 다음 요청용 세션 미리 데움

        var result = route(response.content.commands, text: text, now: now, existing: existing)
        result = await resolveLocations(in: result)   // 장소를 실제 존재하는 곳으로 검증(지어내기 방지)
        lastRequest = text
        return result
    }

    /// create/update 이벤트의 장소를 MapKit으로 검증 — 실제 장소면 그 이름, 없으면 비움.
    private static func resolveLocations(in result: AIResult) async -> AIResult {
        var r = result
        for i in r.events.indices where r.events[i].action != .delete && !r.events[i].location.isEmpty {
            r.events[i].location = await validateLocation(r.events[i].location)
        }
        return r
    }

    /// 장소 문자열 → 실제 장소 이름. 모호해도 검색해 가장 가까운 실제 장소를 찾고, 없으면 ""(지어내지 않음).
    private static func validateLocation(_ query: String) async -> String {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return "" }
        let generic = ["집", "우리집", "집앞", "학교", "회사", "교실", "도서관", "동네", "근처"]
        if generic.contains(q) { return q }   // 일반 장소는 그대로 둠
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.pointOfInterest, .address]
        if let resp = try? await MKLocalSearch(request: request).start(), let item = resp.mapItems.first {
            return item.name ?? q
        }
        return ""   // 실제 장소를 못 찾으면 비움
    }

    // MARK: 슬롯 → 결과(미리보기 일정 + 즉시 액션)
    private static func route(_ commands: [GenCommand], text: String,
                              now: Date, existing: [ExistingEvent]) -> AIResult {
        var events: [ParsedEvent] = []
        var actions: [AIAction] = []
        var seen = Set<UUID>()

        // 단일 명령: 기간(여러 날) 일정 우선 — "7/1부터 7/5까지" 같은 멀티데이를 직접 생성
        if commands.count == 1, commands[0].intent == "scheduleCreate",
           let multi = makeMultiDay(AIKoreanDate.parse(text, now: now), command: commands[0], now: now) {
            return AIResult(events: [multi], actions: [])
        }

        // 한국어 날짜·시각을 코드로 직접 파싱해 슬롯 보정(작은 모델 오류 교정).
        // 문장을 쉼표·'그리고'로 쪼갠 조각 수가 명령 수와 같으면 명령마다, 아니면 단일 명령만.
        var cmds = commands
        let segs = AIKoreanDate.segments(text)
        if cmds.count >= 1 && segs.count == cmds.count {
            for i in cmds.indices { cmds[i] = applyParsed(AIKoreanDate.parse(segs[i], now: now), to: cmds[i]) }
        } else if cmds.count == 1 {
            cmds[0] = applyParsed(AIKoreanDate.parse(text, now: now), to: cmds[0])
        }

        for c in cmds {
            switch c.intent {
            case "scheduleCreate":
                let r = AIDateResolver.resolve(relativeDay: c.relativeDay, weekday: c.weekday, weekOffset: c.weekOffset,
                                               month: c.month, day: c.day,
                                               startHour: c.startHour, startMinute: c.startMinute,
                                               endHour: c.endHour, endMinute: c.endMinute, now: now)
                let title = c.title.trimmingCharacters(in: .whitespaces)
                guard r.hasTime, !title.isEmpty else { break }   // 시각 단서 없으면 생성 안 함
                let rec = Recurrence(rawValue: c.recurrence) ?? .none
                let wds = rec == .weekly ? AIDateResolver.weekdaySet(c.recurrenceWeekdays) : []
                events.append(ParsedEvent(title: title, start: r.start, end: r.end, location: c.location,
                                          action: .create, recurrence: rec, weekdays: wds))

            case "scheduleUpdate":
                guard let t = target(c, text: text, existing: existing) else { break }
                if seen.insert(t.id).inserted { events.append(makeUpdate(c, t, now: now)) }

            case "scheduleDelete":
                if c.bulk {
                    if let key = bulkKey(text: text, existing: existing) {
                        events.append(ParsedEvent(title: key, start: now, end: now,
                                                  location: "", action: .delete, targetID: nil))
                    }
                    break
                }
                let cands = deleteCandidates(text: text, existing: existing)
                if cands.count > 1 {
                    // 후보가 여럿이면 바로 지우지 말고 "어떤 것을 삭제할까요?" 물어봄
                    lastDeleteKeyword = deleteKeyword(text, existing)
                    lastDeleteChosen = nil
                    actions.append(.clarifyDelete(
                        candidates: cands.map { DeleteCandidate(id: $0.id, title: $0.title, start: $0.start) },
                        prompt: "어떤 것을 삭제할까요?"))
                } else if let t = cands.first ?? target(c, text: text, existing: existing) {
                    lastDeleteKeyword = deleteKeyword(text, existing)
                    lastDeleteChosen = t.id
                    if seen.insert(t.id).inserted {
                        events.append(ParsedEvent(title: t.title, start: t.start, end: t.end,
                                                  location: t.location, action: .delete, targetID: t.id))
                    }
                }

            case "mealQuery":
                let day = AIDateResolver.resolveDate(relativeDay: c.relativeDay, weekday: c.weekday,
                                                     weekOffset: c.weekOffset, month: c.month, day: c.day, now: now)
                actions.append(.mealQuery(date: day))

            case "scheduleQuery":
                let day = AIDateResolver.resolveDate(relativeDay: c.relativeDay, weekday: c.weekday,
                                                     weekOffset: c.weekOffset, month: c.month, day: c.day, now: now)
                let kind: AIQueryKind = c.queryKind == "exam" ? .exam : (c.queryKind == "week" ? .week : .day)
                actions.append(.scheduleQuery(kind: kind, day: day))

            case "setAppearance":
                if let a = Appearance(rawValue: c.appearance) { actions.append(.setAppearance(a)) }

            default:
                break   // unknown
            }
        }
        return AIResult(events: events, actions: actions)
    }

    /// 기간(여러 날) 일정 — 파서가 종료일을 찾았으면 멀티데이 ParsedEvent 생성.
    private static func makeMultiDay(_ p: AIKoreanDateTime, command c: GenCommand, now: Date) -> ParsedEvent? {
        guard let endRel = p.endRelativeDay else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let startDay = cal.date(byAdding: .day, value: p.relativeDay ?? 0, to: today) ?? today
        let endDay = cal.date(byAdding: .day, value: endRel, to: today) ?? today
        let start = p.startHour.flatMap { cal.date(bySettingHour: $0, minute: p.startMinute ?? 0, second: 0, of: startDay) } ?? startDay
        let end = p.endHour.flatMap { cal.date(bySettingHour: $0, minute: p.endMinute ?? 0, second: 0, of: endDay) }
            ?? (cal.date(byAdding: .day, value: 1, to: endDay) ?? endDay)   // 종료 시각 없으면 종료일 끝까지
        let t = c.title.trimmingCharacters(in: .whitespaces)
        return ParsedEvent(title: t.isEmpty ? "일정" : t, start: start, end: end, location: c.location, action: .create)
    }

    /// 코드로 파싱한 한국어 날짜·시각을 명령 슬롯에 덮어쓴다(있는 값만).
    private static func applyParsed(_ p: AIKoreanDateTime, to cmd: GenCommand) -> GenCommand {
        var c = cmd
        if let v = p.relativeDay { c.relativeDay = v; c.weekday = ""; c.weekOffset = 0 }
        if let v = p.month { c.month = v; c.weekday = "" }
        if let v = p.day { c.day = v; c.weekday = "" }
        if let v = p.startHour {
            c.startHour = v
            c.startMinute = p.startMinute ?? 0
        }
        if let v = p.endHour {
            c.endHour = v
            c.endMinute = p.endMinute ?? 0
        }
        return c
    }

    // 수정: 날짜 슬롯이 있으면 그 날짜, 없으면 기존 일정 날짜 유지. 시각 슬롯이 있으면 그 시각, 없으면 기존 시각. 길이 유지.
    private static func makeUpdate(_ c: GenCommand, _ t: ExistingEvent, now: Date) -> ParsedEvent {
        let cal = Calendar.current
        let hasDate = !c.weekday.isEmpty || ((1...12).contains(c.month) && (1...31).contains(c.day)) || c.relativeDay != 0
        let baseDay = hasDate
            ? AIDateResolver.resolveDate(relativeDay: c.relativeDay, weekday: c.weekday, weekOffset: c.weekOffset,
                                         month: c.month, day: c.day, now: now)
            : cal.startOfDay(for: t.start)
        let newStart: Date
        if (0...23).contains(c.startHour) {
            newStart = cal.date(bySettingHour: c.startHour, minute: max(0, min(59, c.startMinute)),
                                second: 0, of: baseDay) ?? t.start
        } else if hasDate {
            let h = cal.component(.hour, from: t.start), m = cal.component(.minute, from: t.start)
            newStart = cal.date(bySettingHour: h, minute: m, second: 0, of: baseDay) ?? t.start
        } else {
            newStart = t.start
        }
        let dur = max(0, t.end.timeIntervalSince(t.start))
        let newEnd = newStart.addingTimeInterval(dur > 0 ? dur : 3600)
        return ParsedEvent(title: c.title.isEmpty ? t.title : c.title,
                           start: newStart, end: newEnd,
                           location: c.location.isEmpty ? t.location : c.location,
                           action: .update, targetID: t.id)
    }

    /// 대상: 번호 우선, 없으면 입력에 제목이 든 기존 일정(가장 긴 제목).
    private static func target(_ c: GenCommand, text: String, existing: [ExistingEvent]) -> ExistingEvent? {
        if existing.indices.contains(c.targetIndex - 1) { return existing[c.targetIndex - 1] }
        return existing.filter { !$0.title.isEmpty && text.contains($0.title) }
            .max(by: { $0.title.count < $1.title.count })
    }

    /// 일괄 삭제 키워드: 입력 단어 중 기존 일정 제목에 들어간 것.
    private static func bulkKey(text: String, existing: [ExistingEvent]) -> String? {
        let words = text.components(separatedBy: CharacterSet(charactersIn: " ,.\n")).filter { $0.count >= 2 }
        return words.first(where: { w in existing.contains { $0.title.contains(w) } })
    }

    /// 삭제 대상 키워드: 입력에 통째로 든 제목(가장 긴 것) 우선, 없으면 제목에 들어간 단어.
    private static func deleteKeyword(_ text: String, _ existing: [ExistingEvent]) -> String? {
        if let t = existing.filter({ !$0.title.isEmpty && text.contains($0.title) })
            .map(\.title).max(by: { $0.count < $1.count }) { return t }
        return bulkKey(text: text, existing: existing)
    }

    /// 키워드에 해당하는 삭제 후보 전부(시간 순).
    private static func deleteCandidates(text: String, existing: [ExistingEvent]) -> [ExistingEvent] {
        guard let kw = deleteKeyword(text, existing) else { return [] }
        return existing.filter { !$0.title.isEmpty && ($0.title.contains(kw) || kw.contains($0.title)) }
            .sorted { $0.start < $1.start }
    }

    /// "아니 그거 말고", "다른거" 같은 거부·재요청 짧은 문구인지.
    private static func isRejectionFollowup(_ text: String) -> Bool {
        let t = text.replacingOccurrences(of: " ", with: "")
        let cues = ["그거말고", "그게아니", "다른거", "다른걸", "딴거", "말고다른", "아니다른", "그말고"]
        if cues.contains(where: t.contains) { return true }
        return t.count <= 9 && (t.hasPrefix("아니") || t.hasSuffix("말고"))
    }

    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }

    private static func describe(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible: return "지원하지 않는 기기예요."
        case .appleIntelligenceNotEnabled: return "설정에서 애플 인텔리전스를 켜주세요."
        case .modelNotReady: return "모델 준비 중이에요. 잠시 후 다시 시도하세요."
        @unknown default: return "사용할 수 없어요."
        }
    }
}
#endif
