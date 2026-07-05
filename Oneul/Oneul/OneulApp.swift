import SwiftUI
import SwiftData

extension Notification.Name {
    static let oneulNewEvent = Notification.Name("oneul.newEvent")   // ⌘N
    static let oneulToday = Notification.Name("oneul.today")         // ⌘T
    static let oneulShiftDay = Notification.Name("oneul.shiftDay")   // ⌘←/→ (object: Int -1/+1)
}

@main
struct OneulApp: App {
    let container = Persistence.makeContainer()

    init() {
        NotificationManager.shared.requestAuthorizationIfNeeded()
        #if os(iOS)
        BackgroundRefresh.register(container: container)   // 백그라운드 갱신 작업 등록(launch 전)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 일정") { NotificationCenter.default.post(name: .oneulNewEvent, object: nil) }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .sidebar) {
                Button("오늘로") { NotificationCenter.default.post(name: .oneulToday, object: nil) }
                    .keyboardShortcut("t")
                Button("이전 날") { NotificationCenter.default.post(name: .oneulShiftDay, object: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("다음 날") { NotificationCenter.default.post(name: .oneulShiftDay, object: 1) }
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

        // AI = 메뉴바 상단 ✨ (클릭→자연어 입력 팝오버, 바깥 클릭으로 닫힘)
        MenuBarExtra("Oneul AI", systemImage: "sparkles") {
            AIScheduleView()
                .modelContainer(container)
                .frame(width: 440, height: 520)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
