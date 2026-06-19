import SwiftUI
import SwiftData

@main
struct OneulApp: App {
    let container = Persistence.makeContainer()

    init() {
        NotificationManager.shared.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
