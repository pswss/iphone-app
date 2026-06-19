import SwiftUI

struct RootView: View {
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    private let lang = AppLanguage.shared

    private var colorScheme: ColorScheme? {
        Appearance(rawValue: appearanceRaw)?.colorScheme
    }

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label(lang.tr("오늘"), systemImage: "calendar.day.timeline.left") }

            AIScheduleView()
                .tabItem { Label(lang.tr("AI"), systemImage: "sparkles") }

            SettingsView()
                .tabItem { Label(lang.tr("설정"), systemImage: "gearshape") }
        }
        .tint(Color.appAccentText)
        .preferredColorScheme(colorScheme)
        .environment(\.locale, lang.locale)
    }
}

#Preview {
    RootView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
