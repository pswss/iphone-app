import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity

/// 아이폰 → 애플워치로 오늘 일정을 보낸다(WatchConnectivity, App Group 불필요).
/// updateApplicationContext는 항상 "최신 상태 1개"만 유지하므로 오늘 일정 전송에 적합.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    private override init() { super.init() }

    private var pending: WatchSchedulePayload?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ payload: WatchSchedulePayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { pending = payload; return }   // 활성화 전이면 보류
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? session.updateApplicationContext(["payload": data])
    }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated, let p = pending { pending = nil; send(p) }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
#endif
