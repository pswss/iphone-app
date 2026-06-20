import SwiftUI

@main
struct OneulWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .environment(store)
        }
    }
}
