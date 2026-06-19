import Foundation

/// AI 제공자 — 온디바이스 애플 인텔리전스 전용.
enum AIProvider: String, CaseIterable, Identifiable {
    case appleIntelligence

    var id: String { rawValue }
    var needsKey: Bool { false }
    var displayName: String { "Apple Intelligence" }
    var keychainAccount: String { "apikey-\(rawValue)" }

    /// 클라이언트 생성. (애플 인텔리전스는 키 불필요)
    func makeClient(apiKey: String = "") -> ScheduleAI {
        AppleIntelligenceClient()
    }
}
