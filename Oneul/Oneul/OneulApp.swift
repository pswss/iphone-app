import SwiftUI
import SwiftData

extension Notification.Name {
    static let oneulNewEvent = Notification.Name("oneul.newEvent")   // ⌘N
    static let oneulToday = Notification.Name("oneul.today")         // ⌘T
    static let oneulShiftDay = Notification.Name("oneul.shiftDay")   // ⌘←/→ (object: Int -1/+1)
    static let oneulNewMemo = Notification.Name("oneul.newMemo")     // 메모 섹션에서 + → 새 메모
    static let oneulShowDay = Notification.Name("oneul.showDay")      // 알림 탭 → 그 날짜로 이동 (object: Date)
    static let oneulSelectSection = Notification.Name("oneul.selectSection") // ⌘1~3 (object: Int 0=오늘 1=메모 2=급식)
    static let oneulSyncLA = Notification.Name("oneul.syncLA")       // 설정 진단 카드 → Live Activity 재시작
    static let oneulSearch = Notification.Name("oneul.search")       // ⌘F 일정 검색
    static let oneulAI = Notification.Name("oneul.ai")               // ⇧⌘A AI 입력
    static let oneulRefresh = Notification.Name("oneul.refresh")     // ⌘R 시간표·학사 새로 고침
}

@main
struct OneulApp: App {
    let container = Persistence.makeContainer()

    init() {
        _ = NotificationManager.shared   // delegate 연결(권한 요청은 온보딩 완료 후 — HIG 컨텍스트 요청)
        #if os(iOS)
        Task { @MainActor in PushSync.shared.begin() }   // push-to-start 토큰 구독(앱 꺼져도 LA 자동 시작)
        BackgroundRefresh.register(container: container)   // 백그라운드 갱신 작업 등록(launch 전)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(before: .newItem) {   // replacing이면 'New Window'(⌘N 기본)가 사라짐 → before로 보존
                Button("새 일정") { NotificationCenter.default.post(name: .oneulNewEvent, object: nil) }
                    .keyboardShortcut("n")
                Button("새 메모") { NotificationCenter.default.post(name: .oneulNewMemo, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("AI로 일정 입력…") { NotificationCenter.default.post(name: .oneulAI, object: nil) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("시간표·학사 새로 고침") { NotificationCenter.default.post(name: .oneulRefresh, object: nil) }
                    .keyboardShortcut("r")
            }
            CommandGroup(after: .textEditing) {
                Button("일정 검색…") { NotificationCenter.default.post(name: .oneulSearch, object: nil) }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .sidebar) {
                Button("오늘 보기") { NotificationCenter.default.post(name: .oneulSelectSection, object: 0) }
                    .keyboardShortcut("1")
                Button("메모 보기") { NotificationCenter.default.post(name: .oneulSelectSection, object: 1) }
                    .keyboardShortcut("2")
                Button("급식 보기") { NotificationCenter.default.post(name: .oneulSelectSection, object: 2) }
                    .keyboardShortcut("3")
                Divider()
                Button("오늘로") { NotificationCenter.default.post(name: .oneulToday, object: nil) }
                    .keyboardShortcut("t")
                // 맥 화면은 주 그리드 — 하루 이동은 화면 변화가 없어 주 단위로 통일(상단 ‹›와 동일)
                Button("이전 주") { NotificationCenter.default.post(name: .oneulShiftDay, object: -7) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("다음 주") { NotificationCenter.default.post(name: .oneulShiftDay, object: 7) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(container)
                .frame(width: 480, height: 600)
                .focusEffectDisabled()   // 설정 창(별도 씬) 파란 포커스 링 제거
        }

        // 타임라인 = 메뉴바 아이콘 (클릭→오늘 일정 한눈에) — 위에서 미끄러져 내려오는 등장
        MenuBarExtra("Oneul 타임라인", systemImage: "calendar.day.timeline.left") {
            MenuBarTimelineView()
                .modelContainer(container)
                .frame(width: 340)
                .fixedSize(horizontal: false, vertical: true)
                .menuBarPopIn(.slideDown)
        }
        .menuBarExtraStyle(.window)

        // AI = 메뉴바 상단 ✨ (클릭→자연어 입력 팝오버, 바깥 클릭으로 닫힘) — 반짝 튀어나오는 등장
        MenuBarExtra("Oneul AI", systemImage: "sparkles") {
            AIScheduleView()
                .modelContainer(container)
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)   // 콘텐츠 높이에 딱 맞춤 — 스크롤·빈 여백 없음
                .menuBarPopIn(.sparklePop)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(macOS)
// 메뉴바 팝오버 등장 애니메이션 — 아이콘 성격에 맞는 두 가지
enum MenuBarPopStyle { case slideDown, sparklePop }

private struct MenuBarPopIn: ViewModifier {
    let style: MenuBarPopStyle
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(style == .sparklePop ? (shown ? 1 : 0.88) : 1, anchor: .top)
            .offset(y: style == .slideDown ? (shown ? 0 : -14) : 0)
            .onAppear {
                shown = false
                withAnimation(style == .sparklePop
                              ? .spring(response: 0.32, dampingFraction: 0.62)   // ✨ 통통 튀는 팝
                              : .spring(response: 0.30, dampingFraction: 0.85)) { // 타임라인: 차분한 슬라이드
                    shown = true
                }
            }
            .onDisappear { shown = false }
    }
}

extension View {
    func menuBarPopIn(_ style: MenuBarPopStyle) -> some View { modifier(MenuBarPopIn(style: style)) }
}
#endif
