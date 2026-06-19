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

// MARK: - 언어(한국어/English) 전환

@Observable
final class AppLanguage {
    static let shared = AppLanguage()

    var code: String = UserDefaults.standard.string(forKey: "appLang") ?? "ko" {
        didSet { UserDefaults.standard.set(code, forKey: "appLang") }
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
        "오늘 타임라인": "Today's Timeline",
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
        "일정 생성": "Create Events",
        "생성 중...": "Generating...",
        "＋ 전체 일정에 추가": "＋ Add all",
        "예: 내일 오전 9시 팀 회의, 12시 반 점심, 3시에 헬스장 1시간, 저녁 7시 친구 약속":
            "e.g. Team meeting 9am tomorrow, lunch at 12:30, gym at 3pm for 1h, dinner with a friend at 7pm",
        "일정을 찾지 못했어요. 더 구체적으로 적어 보세요.":
            "Couldn't find any events. Try being more specific.",
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
        "API 키가 없어요. 설정 탭에서 입력해 주세요.": "No API key. Add one in Settings."
    ]
}
