import Foundation

/// 앱 전역 상수. 번들 ID / App Group / iCloud 컨테이너는
/// Xcode에서 본인 팀에 맞게 바꿔도 되지만, 바꾸면 entitlements/project.yml도 함께 맞춰야 합니다.
enum AppConfig {
    /// 앱과 위젯이 데이터를 공유하기 위한 App Group ID.
    static let appGroupID = "group.W9W4CM597R.oneul"   // 팀ID 기반(전역 고유) — com.oneul.app은 선점됨

    /// 잠금화면/다이나믹 아일랜드 Live Activity 식별용.
    static let liveActivityName = "ScheduleActivity"
}
