import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
/// macOS 사이드바 섹션(아이폰의 탭에 대응).
enum MacSection: Hashable, CaseIterable {
    case today, memo, meal
    var title: String {
        switch self {
        case .today: return "오늘"
        case .memo: return "메모"
        case .meal: return "급식"
        }
    }
    var icon: String {
        switch self {
        case .today: return "calendar.day.timeline.left"
        case .memo: return "note.text"
        case .meal: return "fork.knife"
        }
    }
}
#endif

#if os(iOS)
enum IOSTab: Hashable { case today, memo, ai, settings, search }
#endif

struct RootView: View {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("userType") private var userType = "general"
    @AppStorage("didOnboardUserType") private var didOnboard = false   // 첫 실행: 학생 기능 안내
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @State private var fadeSnapshot: UIImage?          // 외형 전환 시 이전 화면을 덮어 서서히 사라지게
    @State private var iosTab: IOSTab = RootView.initialTab()
    @State private var searchActive = false            // 플로팅 검색 — 켜지면 검색 탭이 잠시 사라짐

    /// 시작 탭 — 스크린샷용 "-demoTab=ai" 런치 아규먼트 지원(DEBUG). 명시적 타입으로
    /// 단순하게 유지: 클로저 초기화는 구형 컴파일러에서 타입체크 시간 초과를 유발했다.
    private static func initialTab() -> IOSTab {
        #if DEBUG
        let args: [String] = ProcessInfo.processInfo.arguments
        for arg in args where arg.hasPrefix("-demoTab=") {
            let name: String = String(arg.dropFirst("-demoTab=".count))
            if name == "ai" { return .ai }
            if name == "memo" { return .memo }
            if name == "settings" { return .settings }
        }
        #endif
        return .today
    }
    #endif
    #if os(macOS)
    @State private var macSection: MacSection? = .today
    @State private var showAIPopover = false   // 메인 창 AI 진입점(메뉴바 ✨과 별개)
    #endif
    private let lang = AppLanguage.shared

    private var colorScheme: ColorScheme? {
        Appearance(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some View {
        content
            .tint(Color.appAccentText)
            .preferredColorScheme(colorScheme)
            .environment(\.locale, lang.locale)
            .sheet(isPresented: .constant(!didOnboard)) { onboardSheet }
            .task {
                AppleIntelligenceClient.prewarm()                  // 앱 시작 시 온디바이스 모델 워밍업(AI 첫 입력 렉↓)
                #if canImport(WatchConnectivity)
                WatchSync.shared.activate()                        // 애플워치 연결 활성화
                #endif
                await SchoolAutoRefresh.runIfDue(context: context)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await SchoolAutoRefresh.runIfDue(context: context) }
                } else if phase == .background {
                    #if os(iOS)
                    BackgroundRefresh.schedule()           // 백그라운드 갱신 예약
                    #endif
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        // 검색은 role .search 탭 — 애플 뮤직처럼 탭바 우측 분리 + 탭하면 검색 필로 모핑(시스템 제공)
        TabView(selection: $iosTab) {
            Tab(lang.tr("오늘"), systemImage: "calendar.day.timeline.left", value: IOSTab.today) {
                TodayView()
            }
            Tab(lang.tr("메모"), systemImage: "note.text", value: IOSTab.memo) {
                MemoView()
            }
            Tab("AI", systemImage: "sparkles", value: IOSTab.ai) {
                AIScheduleView()
            }
            Tab(lang.tr("설정"), systemImage: "gearshape", value: IOSTab.settings) {
                SettingsView()
            }
            if !searchActive {   // 검색 중엔 탭이 사라졌다가 완료/취소하면 되돌아옴
                Tab(lang.tr("검색"), systemImage: "magnifyingglass", value: IOSTab.search, role: .search) {
                    Color.clear   // 실제 화면 전환 없음 — 선택 즉시 오버레이로 전환
                }
            }
        }
        .onChange(of: iosTab) { old, new in
            if new == .search {
                iosTab = old == .search ? .today : old          // 현재 탭 유지
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { searchActive = true }
            }
        }
        .overlay {
            if searchActive {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.15)          // 뒤 버튼 오작동 차단 + 배경 탭 → 닫기
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { searchActive = false }
                        }
                    FloatingSearchOverlay(
                        onPick: { day in
                            iosTab = .today
                            NotificationCenter.default.post(name: .oneulShowDay, object: day)
                        },
                        onDismiss: { searchActive = false })
                }
                .transition(.opacity)
            }
        }
        .overlay {
            // 이전 외형 스냅샷을 위에 깔았다가 페이드아웃 → 새 외형이 서서히 드러남(크로스페이드)
            if let fadeSnapshot {
                Image(uiImage: fadeSnapshot)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onChange(of: appearanceRaw) { _, _ in
            guard let img = Self.captureWindow() else { return }
            fadeSnapshot = img                                  // 새 외형 위로 즉시 덮기(이전 모습)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.5)) { fadeSnapshot = nil }   // 서서히 걷어내기
            }
        }
        #else
        // macOS: 사이드바(오늘/메모/급식). AI는 툴바 ✨ 팝오버 + 메뉴바 상주, 설정은 툴바 기어/⌘,.
        NavigationSplitView {
            List(macSections, id: \.self, selection: $macSection) { section in
                Label(lang.tr(section.title), systemImage: section.icon).tag(section)
            }
            .navigationTitle("Oneul")
            .navigationSplitViewColumnWidth(min: 150, ideal: 185, max: 240)
        } detail: {
            Group {
                switch macSection ?? .today {
                case .today: TodayView()
                case .memo: MemoView()
                case .meal: MealView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        NotificationCenter.default.post(name: macSection == .memo ? .oneulNewMemo : .oneulNewEvent, object: nil)
                    } label: {
                        Label(macSection == .memo ? lang.tr("새 메모") : lang.tr("새 일정"), systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {   // 대표 기능(AI)이 메뉴바에만 숨어 있던 문제 — 메인 창에도 진입점
                    Button { showAIPopover = true } label: { Label("AI", systemImage: "sparkles") }
                        .popover(isPresented: $showAIPopover, arrowEdge: .bottom) {
                            AIScheduleView()
                                .frame(width: 420)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                }
                if userType == "student" && macSection != .meal {
                    ToolbarItem(placement: .primaryAction) {   // 시트 대신 섹션 전환(자기 화면 위에 같은 화면이 겹치던 문제 제거)
                        Button { macSection = .meal } label: { Label(lang.tr("급식"), systemImage: "fork.knife") }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink { Label(lang.tr("설정"), systemImage: "gearshape") }
                }
            }
        }
        .frame(minWidth: 840, minHeight: 560)   // 7열 주 그리드가 뭉개지지 않는 최소 크기
        // 포커스 링 전역 제거는 HIG 위반(풀 키보드 액세스 사용자가 위치를 못 봄) → 그리드 등 국소 적용으로 축소
        // 메뉴/툴바 명령 릴레이 — 대상 뷰가 화면에 없으면(다른 섹션) 섹션을 먼저 바꾸고 다음 런루프에 재발행
        .onReceive(NotificationCenter.default.publisher(for: .oneulNewEvent)) { _ in
            if macSection != .today {
                macSection = .today
                DispatchQueue.main.async { NotificationCenter.default.post(name: .oneulNewEvent, object: nil) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneulNewMemo)) { _ in
            if macSection != .memo {
                macSection = .memo
                DispatchQueue.main.async { NotificationCenter.default.post(name: .oneulNewMemo, object: nil) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneulAI)) { _ in showAIPopover = true }   // ⇧⌘A
        .onReceive(NotificationCenter.default.publisher(for: .oneulRefresh)) { _ in                      // ⌘R
            UserDefaults.standard.removeObject(forKey: "lastSchoolRefresh")   // 하루 1회 가드 해제 → 즉시 갱신
            Task { await SchoolAutoRefresh.runIfDue(context: context) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .oneulSelectSection)) { note in
            guard let i = note.object as? Int else { return }
            let all: [MacSection] = [.today, .memo, .meal]
            if i < all.count, macSections.contains(all[i]) { macSection = all[i] }
        }
        #endif
    }

    // 첫 실행 — 사용자 유형 선택(학생 기능이 설정 토글 뒤에 숨어 발견 불가하던 문제)
    private var onboardSheet: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(Color.appAccentText)
            Text(lang.tr("어떻게 사용하시나요?")).font(.title2).bold()
            Text(lang.tr("학생을 선택하면 학교 시간표·급식·학사일정을 자동으로 불러올 수 있어요."))
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 8)
            VStack(spacing: 10) {
                Button {
                    userType = "student"; didOnboard = true
                    NotificationManager.shared.requestAuthorizationIfNeeded()   // 맥락 있는 시점에 권한 요청
                } label: {
                    Label(lang.tr("학생 — 시간표·급식 사용"), systemImage: "graduationcap.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    userType = "general"; didOnboard = true
                    NotificationManager.shared.requestAuthorizationIfNeeded()
                } label: {
                    Text(lang.tr("일반 — 일정·메모만"))
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
            }
            Text(lang.tr("설정에서 언제든 바꿀 수 있어요")).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(28)
        .interactiveDismissDisabled()
        #if os(macOS)
        .frame(width: 420)
        #else
        .presentationDetents([.medium])
        #endif
    }

    #if os(macOS)
    private var macSections: [MacSection] {
        userType == "student"
            ? MacSection.allCases
            : MacSection.allCases.filter { $0 != .meal }
    }
    #endif

    #if os(iOS)
    /// 현재 화면(전환 직전 외형)을 이미지로 캡처. afterScreenUpdates:false라 아직 바뀌지 않은 모습을 담는다.
    private static func captureWindow() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
    #endif
}

#Preview {
    RootView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
