import SwiftUI

/// 빨주노초파남보 — 일정에 **시간 순서대로 자동** 배정되는 색.
/// 사용자가 고르지 않습니다. (앱·위젯 공통)
enum EventPalette {
    /// Apple 시스템 컬러 기반 무지개 7색 RGB.
    private static let rgb: [(r: Double, g: Double, b: Double)] = [
        (1.00, 0.27, 0.23), // 빨 #FF453A
        (1.00, 0.62, 0.04), // 주 #FF9F0A
        (1.00, 0.84, 0.04), // 노 #FFD60A
        (0.19, 0.82, 0.35), // 초 #30D158
        (0.04, 0.52, 1.00), // 파 #0A84FF
        (0.37, 0.36, 0.90), // 남 #5E5CE6
        (0.75, 0.35, 0.95)  // 보 #BF5AF2
    ]
    static let colors: [Color] = rgb.map { Color(red: $0.r, green: $0.g, blue: $0.b) }

    /// 인덱스를 7색 안에서 순환(전체 개수를 모를 때).
    static func color(_ index: Int) -> Color {
        let n = colors.count
        return colors[((index % n) + n) % n]
    }

    /// 일정 수(total)에 맞춰 빨강→보라를 균등 분배.
    /// 8개 이상이면 7색 사이에 어울리는 중간색을 끼워넣어 색 변화가 느려지고,
    /// 7개인 날처럼 **첫 일정=빨강 · 마지막 일정=보라**로 끝난다.
    static func color(_ index: Int, of total: Int) -> Color {
        let n = rgb.count
        guard total > n, total > 1, index >= 0 else { return color(index) }   // 7개 이하: 기존 무지개 그대로
        let i = min(index, total - 1)
        let pos = Double(i) / Double(total - 1) * Double(n - 1)               // 0(빨) … 6(보)
        let lo = min(n - 1, Int(pos)), hi = min(n - 1, lo + 1)
        let t = pos - Double(lo)
        let a = rgb[lo], b = rgb[hi]
        return Color(red: a.r + (b.r - a.r) * t,
                     green: a.g + (b.g - a.g) * t,
                     blue: a.b + (b.b - a.b) * t)
    }
}
