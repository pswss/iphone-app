import Foundation

/// Live Activity 푸시 서버 설정.
/// 실제 URL·키는 로컬에서만 채우고 `git update-index --skip-worktree`로 보호(공개 레포에 비공개 값 금지).
/// 값이 플레이스홀더면 푸시 동기화는 조용히 비활성(로컬 타이머만으로 동작).
enum PushConfig {
    static let serverURL: URL? = URL(string: "https://YOUR-PUSH-WORKER.example.workers.dev")
    static let registerKey = "REPLACE_ME"

    static var enabled: Bool {
        registerKey != "REPLACE_ME" && serverURL?.host?.contains("example") == false
    }
}
