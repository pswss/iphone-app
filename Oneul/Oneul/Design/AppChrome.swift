import SwiftUI
import UIKit

// MARK: - 키보드 광역 내림

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// 빈 곳을 탭하면 키보드를 내린다. (배경 레이어에 붙여 버튼/입력 탭은 방해하지 않음)
    func dismissKeyboardOnBackgroundTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture { UIApplication.shared.endEditing() }
    }
}

// MARK: - 외형(다크/라이트/시스템)

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "시스템"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }

    /// 시스템이면 nil(기기 설정 따름).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - 햅틱

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - 언어(한국어/English) 전환

@Observable
final class AppLanguage {
    static let shared = AppLanguage()

    var code: String = AppLanguage.initialCode() {
        didSet { UserDefaults.standard.set(code, forKey: "appLang") }
    }

    /// 저장값이 없으면 기기 언어 기준(한국어면 ko, 아니면 en). 이후엔 사용자가 바꾼 값 유지.
    private static func initialCode() -> String {
        if let saved = UserDefaults.standard.string(forKey: "appLang") { return saved }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? "ko" : "en"
    }

    var isEnglish: Bool { code == "en" }
    var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "ko_KR") }

    /// 한국어 문자열(키) → 현재 언어 문자열.
    func tr(_ ko: String) -> String {
        isEnglish ? (Self.en[ko] ?? ko) : ko
    }

    static let en: [String: String] = [
        "오늘": "Today",
        "AI": "AI",
        "설정": "Settings",
        "급식": "Meals",
        "오늘 타임라인": "Today's Timeline",
        "타임라인": "Timeline",
        "선택과목 아님 — 빼기": "Not an elective — remove",
        "필수/공통 과목이 잘못 보이면 길게 눌러 빼세요.": "If a required subject is shown here, long-press to remove it.",
        "제외한 과목 %d개 · 되돌리기": "%d removed · Undo",
        "정보": "About",
        "데이터 출처": "Data Source",
        "학사일정·급식·시간표: 나이스(NEIS) 교육정보 개방 포털 (교육부)": "Academic calendar, meals & timetable: NEIS Education Information Open Portal (Korea Ministry of Education)",
        "NEIS API 키": "NEIS API Key",
        "발급받은 키 붙여넣기": "Paste your key",
        "무료 키 발급받기 (open.neis.go.kr)": "Get a free key (open.neis.go.kr)",
        "일정": "Events",
        "일정 없음": "No events",
        "다음 ·": "Next ·",
        "현재 일정 ·": "Now ·",
        "대기 중 · 다음 일정까지": "Free · until next event",
        "오늘 일정 종료": "All done for today",
        "제목": "Title",
        "장소": "Location",
        "위치": "Place",
        "시작": "Start",
        "종료": "End",
        "알림": "Reminder",
        "반복": "Repeat",
        "일정 삭제": "Delete Event",
        "새 일정": "New Event",
        "일정 편집": "Edit Event",
        "취소": "Cancel",
        "저장": "Save",
        "추가": "Add",
        "완료": "Done",
        "이 일정만 삭제": "Delete This Event Only",
        "이후 일정 모두 삭제": "Delete All Future Events",
        "삭제": "Delete",
        "제목 없음": "Untitled",
        "없음": "None",
        "정시": "On time",
        "5분 전": "5 min before",
        "10분 전": "10 min before",
        "30분 전": "30 min before",
        "1시간 전": "1 hr before",
        "매일": "Daily",
        "매주": "Weekly",
        "2주마다": "Every 2 weeks",
        "매달": "Monthly",
        "매년": "Yearly",
        "반복 종료일": "End repeat",
        "종료일": "End date",
        "2차 알림": "Second alert",
        "일정 생성": "Create Events",
        "생성 중...": "Generating...",
        "＋ 전체 일정에 추가": "＋ Add all",
        "예: 내일 오전 9시 팀 회의, 12시 반 점심, 3시에 헬스장 1시간, 저녁 7시 친구 약속":
            "e.g. Team meeting 9am tomorrow, lunch at 12:30, gym at 3pm for 1h, dinner with a friend at 7pm",
        "일정을 찾지 못했어요. 더 구체적으로 적어 보세요.":
            "Couldn't find any events. Try being more specific.",
        "일정을 만들 수 없어요 — 유효한 내용을 입력해 주세요.":
            "Couldn't create a schedule — please enter valid content.",
        "키 받기": "Get key",
        "외형": "Appearance",
        "시스템": "System",
        "라이트": "Light",
        "다크": "Dark",
        "‘시스템’은 기기 설정(다크/라이트)을 따릅니다.": "'System' follows your device setting.",
        "AI API 키": "AI API Keys",
        "연결 확인": "Test",
        "연결됨": "Connected",
        "키 오류": "Invalid key",
        "언어": "Language",
        "API 키가 없어요. 설정 탭에서 입력해 주세요.": "No API key. Add one in Settings.",
        // 설정 · 학교
        "사용자 유형": "User type",
        "일반": "General",
        "학생": "Student",
        "학교 설정 · 시간표 가져오기": "School · Import timetable",
        "학교 설정": "School setup",
        "학교 검색": "Search school",
        "학교 이름 (예: 서울고등학교)": "School name (e.g. Seoul High)",
        "검색": "Search",
        "검색 결과": "Results",
        "변경": "Change",
        "학년": "Grade",
        "반": "Class",
        "교시 시간 조정": "Adjust period times",
        // 시간표/선택과목
        "시간표 가져오기": "Import timetable",
        "시간표 만들기": "Create timetable",
        "만드는 중…": "Creating…",
        "학년 전체 시간표 불러오는 중…": "Loading the grade's timetable…",
        "이 학교·학년의 시간표가 NEIS에 없어요. 그리드에서 직접 추가해 주세요.":
            "No timetable for this school/grade in NEIS. Add classes in the grid.",
        "선택과목이 없는 공통 시간표예요. 바로 만들 수 있어요.":
            "A common timetable with no electives. You can create it now.",
        "본인이 듣는 선택과목을 모두 체크하세요. 공통 과목은 자동으로 들어가요.":
            "Check every elective you take. Common subjects are added automatically.",
        "다음": "Next",
        "뒤로": "Back",
        "배치된 선택과목이에요. 일정이 안 맞는 과목은 고쳐주세요.":
            "Here's the placement. Fix any period that looks wrong.",
        "시간표를 추가했어요 (수업 %d개). 새 학사일정·다음 학기는 자동으로 갱신돼요.":
            "Timetable added (%d classes). New school events and next semester update automatically.",
        // 그리드/급식
        "종일": "All day",
        "놓으면 삭제": "Release to delete",
        "여기로 끌어 삭제": "Drag here to delete",
        "급식 정보가 없어요": "No meal info",
        "설정 → 학생 → 학교 설정에서\n학교를 먼저 등록하세요":
            "Register your school first in\nSettings → Student → School",
        // AI
        "수정": "Edit",
        "AI · 온디바이스 (키 불필요)": "AI · on-device (no key)",
        "AI 비서": "AI Assistant",
        "실행": "Run",
        "실행 중…": "Running…",
        "적용하기": "Apply",
        "예: 내일 9시 팀 회의 추가, 금요일 약속 취소, 점심 1시로 옮겨줘":
            "e.g. Add a team meeting at 9am tomorrow, cancel Friday's plan, move lunch to 1pm"
    ]
}
