import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
/// macOS 사이드바 섹션(아이폰의 탭에 대응).
enum MacSection: Hashable, CaseIterable {
    case today, meal
    var title: String {
        switch self {
        case .today: return "오늘"
        case .meal: return "급식"
        }
    }
    var icon: String {
        switch self {
        case .today: return "calendar.day.timeline.left"
        case .meal: return "fork.knife"
        }
    }
}
#endif

struct RootView: View {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("userType") private var userType = "general"
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @State private var fadeSnapshot: UIImage?          // 외형 전환 시 이전 화면을 덮어 서서히 사라지게
    #endif
    #if os(macOS)
    @State private var macSection: MacSection? = .today
    @State private var showMeal = false
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
        TabView {
            TodayView()
                .tabItem { Label(lang.tr("오늘"), systemImage: "calendar.day.timeline.left") }

            if userType == "student" {
                MealView()
                    .tabItem { Label(lang.tr("급식"), systemImage: "fork.knife") }
            }

            AIScheduleView()
                .tabItem { Label(lang.tr("AI"), systemImage: "sparkles") }

            SettingsView()
                .tabItem { Label(lang.tr("설정"), systemImage: "gearshape") }
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
        // macOS: 사이드바(Today/급식). AI는 상단 툴바, 설정은 앱 메뉴(⌘,).
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
                case .meal: MealView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { NotificationCenter.default.post(name: .oneulNewEvent, object: nil) } label: {
                        Label(lang.tr("새 일정"), systemImage: "plus")
                    }
                }
                if userType == "student" {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showMeal = true } label: { Label(lang.tr("급식"), systemImage: "fork.knife") }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink { Label(lang.tr("설정"), systemImage: "gearshape") }
                }
            }
            .sheet(isPresented: $showMeal) {
                NavigationStack {
                    MealView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(lang.tr("닫기")) { showMeal = false }
                            }
                        }
                }
                .frame(minWidth: 420, minHeight: 540)
            }
        }
        .focusEffectDisabled()   // 맥 파란 포커스 링 전역 제거(버튼/셀/월 헤더 등)
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
