import SwiftUI
import SwiftData
import UIKit

struct RootView: View {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("userType") private var userType = "general"
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var fadeSnapshot: UIImage?          // 외형 전환 시 이전 화면을 덮어 서서히 사라지게
    private let lang = AppLanguage.shared

    private var colorScheme: ColorScheme? {
        Appearance(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some View {
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
        .tint(Color.appAccentText)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, lang.locale)
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
            }
        }
    }

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
}

#Preview {
    RootView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
