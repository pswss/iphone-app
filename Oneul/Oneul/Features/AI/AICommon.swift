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
    var inferredPM: Bool = false         // 오전/오후 미표기를 맥락으로 오후 해석함(근거 표시용)
    var amPmAmbiguous: Bool = false      // 오전/오후를 확신 못 함 → 사용자에게 확인 질문
    var deleteSeries: Bool = false       // delete 시 같은 시리즈의 이후 반복 전체 삭제
}

/// 직전 삭제 맥락 — "아니 그거 말고" 후속에서 다른 후보를 제시하기 위한 공용 상태(빠른 경로·모델 공용).
enum AIDeleteContext {
    static var lastKeyword: String?
    static var lastChosen: UUID?
}

/// 맨숫자 시각(오전/오후 미표기)의 해석에 쓰는 사용자 맥락.
/// 근거: docs/AI_시간맥락모델.md (학원 조례·학교 등하교·통계청 생활시간조사 기반).
struct AIParseContext {
    /// 방학 여부 — true=방학, false=학기중, nil=모름(학사일정 데이터 없음).
    var vacation: Bool? = nil
    /// 제목 → 기존 일정들의 시작 시(0-23). 같은 과목의 등록 패턴을 통계 모델보다 우선.
    var learnedHours: [String: Set<Int>] = [:]
}

/// AI에 컨텍스트로 넘기는 기존(다가오는) 일정 스냅샷.
struct ExistingEvent: Hashable {
    let id: UUID
    let title: String
    let start: Date
    let end: Date
    let location: String
}

