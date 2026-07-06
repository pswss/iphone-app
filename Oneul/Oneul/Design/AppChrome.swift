import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - 키보드 광역 내림

#if canImport(UIKit)
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

/// 현재 포커스(키보드)를 내린다. macOS엔 소프트 키보드가 없어 first responder만 해제.
func endEditingGlobally() {
    #if canImport(UIKit)
    UIApplication.shared.endEditing()
    #elseif canImport(AppKit)
    NSApp.keyWindow?.makeFirstResponder(nil)
    #endif
}

extension View {
    /// 빈 곳을 탭하면 키보드를 내린다. (배경 레이어에 붙여 버튼/입력 탭은 방해하지 않음)
    func dismissKeyboardOnBackgroundTap() -> some View {
        contentShape(Rectangle())
            .onTapGesture { endEditingGlobally() }
    }

    /// `.navigationBarTitleDisplayMode(.inline)` — macOS엔 없는 모디파이어라 no-op.
    @ViewBuilder
    func navBarInline() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
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
    enum Style { case light, medium, heavy, soft, rigid }
    enum Notice { case success, warning, error }

    static func impact(_ style: Style) {
        #if canImport(UIKit)
        let s: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .light: s = .light; case .medium: s = .medium; case .heavy: s = .heavy
        case .soft: s = .soft; case .rigid: s = .rigid
        }
        UIImpactFeedbackGenerator(style: s).impactOccurred()
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
    static func notify(_ type: Notice) {
        #if canImport(UIKit)
        let t: UINotificationFeedbackGenerator.FeedbackType
        switch type {
        case .success: t = .success; case .warning: t = .warning; case .error: t = .error
        }
        UINotificationFeedbackGenerator().notificationOccurred(t)
        #elseif canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
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
        // 개인정보 · AI/출처
        "AI: Apple Intelligence(온디바이스) · 학사일정·급식·시간표: 나이스(NEIS) 교육정보 개방 포털(교육부)": "AI: Apple Intelligence (on-device) · Academic calendar, meals & timetable: NEIS Education Information Open Portal (Korea Ministry of Education)",
        "개인정보": "Privacy",
        "개인정보 처리방침": "Privacy Policy",
        "모든 데이터 초기화": "Reset all data",
        "정말 모든 데이터를 지울까요?": "Erase all data?",
        "이 기기의 모든 일정·학교 설정이 삭제됩니다. 되돌릴 수 없어요.": "All events and school settings on this device will be deleted. This can't be undone.",
        "초기화": "Reset",
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
        "Apple Intelligence · 온디바이스 (키 불필요)": "Apple Intelligence · on-device (no key)",
        "AI 비서": "AI Assistant",
        "실행": "Run",
        "실행 중…": "Running…",
        "적용하기": "Apply",
        "예: 내일 9시 팀 회의 추가, 금요일 약속 취소, 점심 1시로 옮겨줘":
            "e.g. Add a team meeting at 9am tomorrow, cancel Friday's plan, move lunch to 1pm",
        "예: 매주 월요일 7시 영어학원 · 다음주 월요일 급식 · 내일 뭐 있어? · 다크모드로 바꿔줘":
            "e.g. English academy every Monday at 7 · Next Monday's lunch · What's on tomorrow? · Switch to dark mode",
        "무엇을 할지 이해하지 못했어요. 다시 말해 주세요.": "I couldn't understand that. Please try again.",
        "그 표현은 도와드리기 어려워요. 일정 내용을 부드럽게 바꿔서 다시 말해 주세요.":
            "I can't help with that phrasing. Please reword your event and try again.",
        "적용할 대상을 찾지 못했어요.": "Couldn't find anything to apply this to.",
        "제목이 같은 일정 전부": "All events with this title",
        "삭제했어요": "Deleted",
        "모드로 바꿨어요.": "mode enabled.",
        "일정이 없어요.": "No events.",
        "다가오는 시험이 없어요.": "No upcoming exams.",
        "학교를 먼저 등록해 주세요 (설정 → 학생).": "Register your school first (Settings → Student).",
        // 메모
        "메모": "Notes",
        "새 메모": "New Note",
        "메모가 없어요": "No notes",
        "텍스트(.txt)로 내보내기": "Export as text (.txt)",
        "마크다운(.md)으로 내보내기": "Export as Markdown (.md)",
        "단락 스타일": "Paragraph Style",
        "제목 2": "Heading",
        "소제목": "Subheading",
        "본문": "Body",
        "굵게": "Bold",
        "기울임": "Italic",
        "사진": "Photo",
        "파일": "File",
        "일정 복사됨 · 빈 곳을 눌러 붙여넣기": "Event copied · tap empty space to paste",
        "반복 일정 수정": "Edit Repeating Event",
        "이 일정만 수정": "Edit This Event Only",
        "이후 일정 모두 수정": "Edit All Future Events",
        "메모 검색": "Search notes",
        "잘라내기": "Cut",
        "복사": "Copy",
        "복제": "Duplicate",
        "일정 검색": "Search Events",
        "제목이나 장소": "Title or location",
        "제목이나 장소로 일정을 찾아요": "Find events by title or location",
        "검색 결과가 없어요": "No results",
        "시간표를 불러오지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.":
            "Couldn't load the timetable. Check your connection and try again.",
        "다시 시도": "Try Again",
        "현재 위치": "Current location",
        "현재 위치 사용": "Use current location",
        "장소 검색": "Search places",
        "\"%@\" 직접 입력": "Use \"%@\" as typed",
        "어떻게 사용하시나요?": "How will you use Oneul?",
        "학생을 선택하면 학교 시간표·급식·학사일정을 자동으로 불러올 수 있어요.":
            "Choose Student to auto-import your school timetable, meals and calendar.",
        "학생 — 시간표·급식 사용": "Student — timetable & meals",
        "일반 — 일정·메모만": "General — events & notes only",
        "설정에서 언제든 바꿀 수 있어요": "You can change this anytime in Settings",
        "제목이 같은 일정 %d개 삭제": "Deletes %d events with this title",
        "하루 전": "1 day before",
        "메모 (선택)": "Notes (optional)",
        "일정 알림": "Event alerts",
        "켜짐": "On",
        "설정에서 켜기": "Enable in Settings",
        "허용하기": "Allow",
        "급식을 불러오지 못했어요": "Couldn't load meals",
        "주말에는 급식이 없어요": "No meals on weekends",
        "메모 %d개 삭제됨": "%d note(s) deleted",
        "실행 취소": "Undo",
        "가져오기": "Import",
        "애플 캘린더에서 가져오기": "Import from Apple Calendar",
        "일정 %d개를 가져왔어요 (오늘부터 90일)": "Imported %d events (next 90 days)",
        "캘린더 접근이 거부됐어요. 시스템 설정에서 허용해 주세요.":
            "Calendar access denied. Allow it in System Settings.",
        "할 일": "To-do",
        "AI 일정": "AI Events",
        "새 메모 작성": "New Note",
        "학교 설정하기": "Set up school",
        "실시간 활동 (잠금화면·다이나믹 아일랜드)": "Live Activity (Lock Screen · Dynamic Island)",
        "지금 시작": "Start now",
        "다가오는 일정이 없어요": "No upcoming events",
        "남은": "left",
        "다음까지": "next in",
        "현재": "Now",
        "다음": "Next",
        "진행 중인 일정 없음": "No active event",
        "배치할 교시를 찾지 못한 과목: %@ — 미리보기에서 직접 지정해 주세요.":
            "Couldn't place: %@ — assign them manually in the preview.",
        "마이크·음성 인식 권한이 꺼져 있어요. 시스템 설정에서 허용해 주세요.":
            "Microphone/speech permission is off. Allow it in System Settings.",
        "새 학년이 시작됐어요 — 설정에서 학년·반을 다시 설정해 주세요":
            "A new school year has started — update your grade & class in Settings",
        // 맥 주 그리드/공통
        "닫기": "Close",
        "주": "Week",
        "주요 일정": "Featured",
        "진행 중": "Ongoing"
    ]
}
