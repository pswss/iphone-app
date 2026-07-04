import SwiftUI
import SwiftData

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
    }
}
