import SwiftUI

/// 리퀴드 글래스 느낌의 카드 배경.
///
/// 기본 구현은 `.ultraThinMaterial`로 어떤 iOS 버전에서도 안정적으로 컴파일됩니다.
/// iOS 26 이상에서 진짜 Liquid Glass를 쓰려면 아래 `body`를 다음으로 바꾸면 됩니다:
/// ```swift
/// content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
/// ```
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: shape)   // iOS 26 진짜 Liquid Glass(굴절·렌즈·하이라이트) — ultraThinMaterial 대체
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)   // 유리가 깊이를 주므로 그림자는 아주 은은하게
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

/// 강조 색 채움 버튼(추가/저장 등) — 포인트 컬러(화이트/남색) 사용.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.appOnAccent)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.tint(Color.appAccent).interactive(),   // 틴트 Liquid Glass(프로미넌트 CTA)
                         in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}
