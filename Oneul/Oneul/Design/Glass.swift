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
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .clipShape(shape)
            .shadow(color: .black.opacity(0.10), radius: 5, x: 0, y: 2)    // 가까운 약한 그림자
            .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 12)   // 먼 부드러운 그림자(자연스러운 깊이)
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
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }
}
