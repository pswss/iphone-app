import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 애플 인텔리전스(온디바이스, iOS 26+) 기반 일정 생성/수정. 키 불필요.
/// 미지원 기기/구버전에서는 사용 불가 에러를 던져 다른 AI로 안내.
struct AppleIntelligenceClient: ScheduleAI {
    func generateSchedule(from text: String, now: Date, existing: [ExistingEvent]) async throws -> [ParsedEvent] {
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
    @Generable
    struct GenSchedule {
        @Guide(description: "할 일이나 시간이 담긴 일정/약속이거나 기존 일정 수정·삭제 요청이면 true. 단순 단어·이름·노래제목·사물명 등 일정과 무관하면 false")
        var isSchedule: Bool
        @Guide(description: "만들거나 수정/삭제할 일정 목록. isSchedule이 false면 빈 배열")
        var events: [GenEvent]
    }

    @Generable
    struct GenEvent {
        @Guide(description: "동작: 새 일정이면 create, 기존 일정 수정이면 update, 기존 일정 삭제면 delete")
        var action: String
        @Guide(description: "update/delete일 때만 대상 기존 일정 번호([1],[2]…). create면 0")
        var targetIndex: Int
        @Guide(description: "일정 제목")
        var title: String
        @Guide(description: "시작 시각, ISO8601 형식 (예: 2026-06-20T09:00:00+09:00)")
        var start: String
        @Guide(description: "종료 시각, ISO8601 형식. 없으면 시작+1시간")
        var end: String
        @Guide(description: "장소. 없으면 빈 문자열")
        var location: String
    }

    // 정적 instructions로 세션 1개 재사용 (동적 컨텍스트는 프롬프트로 전달 → prewarm 가능).
    private static let instructions = """
    너는 한국어 일정 비서다. 사용자의 자연어를 해석해 일정을 새로 만들거나, 기존 일정을 수정/삭제한다.
    - 일정/계획/약속/할 일이 아니면 isSchedule=false, events=[]. 특히 시간이나 할 일이 없는 단순 단어·이름·노래제목·사물명·잡담(예: "아리랑", "안녕", "사과")은 반드시 isSchedule=false.
    - 새 일정: action="create", targetIndex=0.
    - "○○ 취소/삭제/지워" 등 기존 일정을 없애라는 요청: action="delete", targetIndex=그 일정 번호.
    - "○○를 △시로 바꿔/옮겨/변경" 등 기존 일정 변경: action="update", targetIndex=그 일정 번호, 바뀐 내용 반영.
    - start/end는 ISO8601(타임존 오프셋 포함). 종료 미지정 시 시작+1시간.
    - 상대 표현(내일/오늘/오후/저녁/점심 등)은 프롬프트의 현재 시각 기준 절대 시각으로.
    - 장소 없으면 location="".
    """

    // 매 요청마다 새 세션을 쓴다(대화가 누적돼 컨텍스트를 초과하지 않도록). 1개 미리 데워 첫 응답 지연만 줄인다.
    private static var _primed: LanguageModelSession?

    static func prewarm() {
        guard case .available = SystemLanguageModel.default.availability else { return }
        guard _primed == nil else { return }
        let s = LanguageModelSession(instructions: instructions)
        _primed = s
        s.prewarm()
    }

    static func availability() -> AIValidation {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ok
        case .unavailable(let reason):
            return .failed(describe(reason))
        }
    }

    static func generate(from text: String, now: Date, existing: [ExistingEvent]) async throws -> [ParsedEvent] {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AppleIntelligenceUnavailable(
                reason: "애플 인텔리전스를 사용할 수 없어요 (설정에서 켜야 할 수 있어요).")
        }

        let isoNow = ISO8601DateFormatter().string(from: now)
        var prompt = "현재 시각: \(isoNow) (\(TimeZone.current.identifier)).\n"
        if !existing.isEmpty {
            prompt += "기존 일정 목록(수정/삭제 대상):\n"
            for (i, e) in existing.enumerated() {
                prompt += "[\(i + 1)] \(shortDate(e.start)) \(e.title)\n"
            }
        }
        prompt += "\n요청: \(text)"

        // 미리 데운 세션을 1회만 쓰고 버린다(transcript 누적 → 컨텍스트 초과 방지).
        let session = _primed ?? LanguageModelSession(instructions: instructions)
        _primed = nil
        let response = try await session.respond(to: prompt, generating: GenSchedule.self)
        prewarm()   // 다음 요청을 위해 새 세션을 미리 데움
        guard response.content.isSchedule else { return [] }
        let timeCue = hasTimeCue(text)   // 새 일정은 입력에 시간 단서가 있어야 생성(무작위 글자 차단)

        return response.content.events.compactMap { e -> ParsedEvent? in
            let action = ParsedEvent.Action(rawValue: e.action) ?? .create
            let target = ref(e.targetIndex, in: existing)
            switch action {
            case .delete:
                guard let t = target else { return nil }
                return ParsedEvent(title: t.title, start: t.start, end: t.end,
                                   location: t.location, action: .delete, targetID: t.id)
            case .update:
                guard let t = target else { return nil }
                let newStart = AICommon.parseDate(e.start)
                let s = newStart ?? t.start
                let end = AICommon.parseDate(e.end) ?? (newStart != nil ? s.addingTimeInterval(3600) : t.end)
                return ParsedEvent(title: e.title.isEmpty ? t.title : e.title, start: s, end: end,
                                   location: e.location.isEmpty ? t.location : e.location,
                                   action: .update, targetID: t.id)
            case .create:
                guard timeCue,
                      !e.title.trimmingCharacters(in: .whitespaces).isEmpty,
                      let s = AICommon.parseDate(e.start) else { return nil }
                let end = AICommon.parseDate(e.end) ?? s.addingTimeInterval(3600)
                return ParsedEvent(title: e.title, start: s, end: end, location: e.location, action: .create)
            }
        }
    }

    private static func ref(_ idx: Int, in existing: [ExistingEvent]) -> ExistingEvent? {
        existing.indices.contains(idx - 1) ? existing[idx - 1] : nil
    }
    private static func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }

    /// 입력에 시간/날짜 단서(숫자, 오전·오후, 내일·요일 등)가 있는지 — 새 일정 생성의 최소 조건.
    private static func hasTimeCue(_ text: String) -> Bool {
        if text.range(of: #"\d"#, options: .regularExpression) != nil { return true }
        let cues = ["오전", "오후", "새벽", "아침", "점심", "저녁", "밤", "정오", "자정",
                    "내일", "오늘", "모레", "글피", "다음주", "이번주", "다음 주", "이번 주", "주말", "평일",
                    "월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일",
                    "am", "pm", "AM", "PM"]
        return cues.contains { text.contains($0) }
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
