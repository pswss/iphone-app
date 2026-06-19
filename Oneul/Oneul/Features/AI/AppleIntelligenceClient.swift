import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 애플 인텔리전스(온디바이스, iOS 26+) 기반 일정 생성. 키 불필요.
/// 미지원 기기/구버전에서는 사용 불가 에러를 던져 다른 AI로 안내.
struct AppleIntelligenceClient: ScheduleAI {
    func generateSchedule(from text: String, now: Date) async throws -> [ParsedEvent] {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            return try await AppleAI.generate(from: text, now: now)
        }
        #endif
        throw AppleIntelligenceUnavailable(
            reason: "이 기기에서는 애플 인텔리전스를 쓸 수 없어요. 다른 AI를 선택하세요.")
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
        @Guide(description: "사용자 문장에서 추출한 일정 목록")
        var events: [GenEvent]
    }

    @Generable
    struct GenEvent {
        @Guide(description: "일정 제목")
        var title: String
        @Guide(description: "시작 시각, ISO8601 형식 (예: 2026-06-20T09:00:00+09:00)")
        var start: String
        @Guide(description: "종료 시각, ISO8601 형식. 없으면 시작+1시간")
        var end: String
        @Guide(description: "장소. 없으면 빈 문자열")
        var location: String
    }

    static func availability() -> AIValidation {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ok
        case .unavailable(let reason):
            return .failed(describe(reason))
        }
    }

    static func generate(from text: String, now: Date) async throws -> [ParsedEvent] {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AppleIntelligenceUnavailable(
                reason: "애플 인텔리전스를 사용할 수 없어요 (설정에서 켜야 할 수 있어요).")
        }

        let isoNow = ISO8601DateFormatter().string(from: now)
        let tz = TimeZone.current.identifier
        let instructions = """
        너는 한국어 일정 비서다. 사용자의 자연어를 현재 시각 기준으로 해석해 일정으로 만든다.
        현재 시각: \(isoNow) (\(tz)).
        - start/end는 ISO8601(타임존 오프셋 포함).
        - 종료 시각이 명시 안 되면 시작 +1시간.
        - 내일/오늘/오후/저녁/점심 같은 상대 표현은 절대 시각으로 변환.
        - 장소가 없으면 location은 빈 문자열.
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: text, generating: GenSchedule.self)

        return response.content.events.compactMap { e in
            guard let s = AICommon.parseDate(e.start) else { return nil }
            let end = AICommon.parseDate(e.end) ?? s.addingTimeInterval(3600)
            return ParsedEvent(title: e.title, start: s, end: end, location: e.location)
        }
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
