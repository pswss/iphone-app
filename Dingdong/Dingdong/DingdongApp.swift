import SwiftUI
import UserNotifications

@main
struct DingdongApp: App {
    init() {
        _ = NotificationDelegate.shared            // 포그라운드 배너
        ToneStore.shared.installPresetsIfNeeded()  // 기본 알림음(자체 신디사이즈) 설치
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// 앱 사용 중에도 배너·사운드가 뜨게.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

// MARK: - 공통 룩(파스텔 그라데이션 + 리퀴드 글래스)

struct AppBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 1.00, green: 0.93, blue: 0.90),
                                Color(red: 0.93, green: 0.94, blue: 1.00),
                                Color(red: 0.90, green: 0.98, blue: 0.95)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        self.glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension Color {
    static let accentDeep = Color(red: 0.22, green: 0.24, blue: 0.45)   // 오늘(Oneul) 계열 남색
}
