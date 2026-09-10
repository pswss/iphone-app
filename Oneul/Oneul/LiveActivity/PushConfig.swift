import Foundation

/// Live Activity 푸시 서버 설정.
/// 실제 URL·키는 Secrets.swift(gitignore)에만 — 이 파일은 커밋해도 안전하다.
/// 값이 비어 있으면 푸시 동기화는 조용히 비활성(로컬 타이머만으로 동작).
enum PushConfig {
    static let serverURL: URL? = URL(string: Secrets.pushServerURL)
    static let registerKey = Secrets.pushRegisterKey

    static var enabled: Bool {
        registerKey.count >= 32 && serverURL?.scheme == "https" && serverURL?.host?.contains("example") == false
    }
}
