import Foundation

/// AI가 만들어낸 일정 한 건(저장 전). 새로 만들거나(create) 기존 일정 수정/삭제(update/delete).
struct ParsedEvent: Identifiable, Hashable {
    enum Action: String, Hashable { case create, update, delete }
    let id = UUID()
    var title: String
    var start: Date
    var end: Date
    var location: String
    var action: Action = .create
    var targetID: UUID? = nil   // update/delete 대상 기존 일정 id
    var recurrence: Recurrence = .none   // 반복 일정(create 적용 시 EventActions.create로)
    var weekdays: Set<Int> = []          // 매주 특정 요일(1=일…7=토)
    var endDate: Date? = nil             // 반복 종료일(없으면 기본 1년)
}

/// AI에 컨텍스트로 넘기는 기존(다가오는) 일정 스냅샷.
struct ExistingEvent: Hashable {
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let location: String
}

enum AIError: LocalizedError {
    case missingKey
    case http(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .missingKey: return "API 키가 없어요. 설정에서 입력해 주세요."
        case .http(let code, let msg): return "요청 실패 (HTTP \(code)) \(msg.prefix(200))"
        case .decoding: return "응답을 해석하지 못했어요."
        }
    }
}

/// 키 연결 검증 결과.
enum AIValidation: Equatable {
    case ok
    case failed(String)
}

/// 자연어 → 앱 동작(일정 변경 미리보기 + 즉시 액션) + 키 검증 인터페이스.
protocol ScheduleAI {
    func generateSchedule(from text: String, now: Date, existing: [ExistingEvent]) async throws -> AIResult
    func validate() async -> AIValidation
}

extension ScheduleAI {
    func generateSchedule(from text: String) async throws -> AIResult {
        try await generateSchedule(from: text, now: .now, existing: [])
    }
}

/// 제공자 간 공유되는 스키마/프롬프트/파싱 헬퍼.
enum AICommon {
    /// Claude/OpenAI 용 JSON Schema (Gemini는 자체 스키마 별도).
    static let eventsJSONSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "events": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "start": ["type": "string"],
                        "end": ["type": "string"],
                        "location": ["type": "string"]
                    ],
                    "required": ["title", "start", "end", "location"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["events"],
        "additionalProperties": false
    ]

    static func systemPrompt(now: Date) -> String {
        let isoNow = ISO8601DateFormatter().string(from: now)
        let tz = TimeZone.current.identifier
        return """
        너는 한국어 일정 비서다. 사용자의 자연어를 현재 시각 기준으로 해석해 일정 목록(JSON)으로 변환한다.
        - 현재 시각: \(isoNow) (\(tz))
        - start/end는 ISO 8601 형식(타임존 오프셋 포함).
        - 종료 시각이 명시되지 않으면 시작 +1시간.
        - "내일/오늘/오후/저녁/점심" 같은 상대 표현은 현재 시각 기준 절대 시각으로 변환.
        - 장소가 없으면 location은 빈 문자열.
        반드시 {"events":[...]} 형태의 JSON만 출력한다.
        """
    }

    /// JSON 이벤트 배열 → ParsedEvent.
    static func parse(_ events: [[String: Any]]) -> [ParsedEvent] {
        events.compactMap { dict in
            guard
                let title = dict["title"] as? String,
                let startStr = dict["start"] as? String,
                let start = parseDate(startStr)
            else { return nil }
            let end = (dict["end"] as? String).flatMap(parseDate) ?? start.addingTimeInterval(3600)
            return ParsedEvent(title: title, start: start, end: end,
                               location: dict["location"] as? String ?? "")
        }
    }

    static func parseDate(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    /// 인증용 가벼운 GET 요청으로 키 검증.
    static func validateGET(_ request: URLRequest) async -> AIValidation {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200..<300).contains(code) { return .ok }
            if code == 401 || code == 403 { return .failed("\(AppLanguage.shared.tr("키 오류")) (\(code))") }
            return .failed("HTTP \(code)")
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 응답 본문(JSON 문자열) → events 배열.
    static func extractEvents(fromJSONText text: String) -> [[String: Any]]? {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = payload["events"] as? [[String: Any]]
        else { return nil }
        return events
    }
}
