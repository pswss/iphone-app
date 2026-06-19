import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("userType") private var userType = "general"
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
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
        .task {
            AppleIntelligenceClient.prewarm()                  // 앱 시작 시 온디바이스 모델 워밍업(AI 첫 입력 렉↓)
            await SchoolAutoRefresh.runIfDue(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await SchoolAutoRefresh.runIfDue(context: context) }
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
