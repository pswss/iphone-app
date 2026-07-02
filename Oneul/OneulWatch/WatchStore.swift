import Foundation
import WatchConnectivity
import WidgetKit

/// 아이폰에서 받은 오늘 일정을 보관. 마지막 값은 캐시해 두어 앱을 다시 열어도 보인다.
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    var payload: WatchSchedulePayload = .empty

    private let cacheKey = "watchPayload"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let p = try? JSONDecoder().decode(WatchSchedulePayload.self, from: data) {
            payload = p
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data,
              let p = try? JSONDecoder().decode(WatchSchedulePayload.self, from: data) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        // 컴플리케이션(별도 프로세스)이 읽도록 App Group에 공유 스냅샷 저장 + 워치 페이스 갱신
        SharedStore.writeToday(HomeSnapshot(
            dayLabel: p.dayLabel, dayStart: p.dayStart, dayEnd: p.dayEnd, segments: p.events,
            currentTitle: p.currentTitle, currentEnd: p.currentEnd,
            nextTitle: p.nextTitle, nextStart: p.nextStart, updatedAt: p.updatedAt))
        WidgetCenter.shared.reloadAllTimelines()
        Task { @MainActor in self.payload = p }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)   // 활성화 직후 마지막으로 받은 상태 반영
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    // iOS SDK 컨텍스트에서도 프로토콜을 만족하도록(watchOS에선 제외됨)
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {}
    #endif
}
