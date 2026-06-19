import SwiftUI

/// 빨주노초파남보 — 일정에 **시간 순서대로 자동** 배정되는 색.
/// 사용자가 고르지 않습니다. (앱·위젯 공통)
enum EventPalette {
    /// Apple 시스템 컬러 기반 무지개 7색.
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.27, blue: 0.23), // 빨 #FF453A
        Color(red: 1.00, green: 0.62, blue: 0.04), // 주 #FF9F0A
        Color(red: 1.00, green: 0.84, blue: 0.04), // 노 #FFD60A
        Color(red: 0.19, green: 0.82, blue: 0.35), // 초 #30D158
        Color(red: 0.04, green: 0.52, blue: 1.00), // 파 #0A84FF
        Color(red: 0.37, green: 0.36, blue: 0.90), // 남 #5E5CE6
        Color(red: 0.75, green: 0.35, blue: 0.95)  // 보 #BF5AF2
    ]

    /// 인덱스를 7색 안에서 순환시켜 색을 반환. (일정이 7개를 넘어도 안전)
    static func color(_ index: Int) -> Color {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }
}
