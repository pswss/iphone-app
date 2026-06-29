import SwiftUI
import UIKit

extension Color {
    /// 앱 포인트 컬러 — 라이트=화이트, 다크=남색.
    static let appAccent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.29, blue: 0.63, alpha: 1)   // 남색
            : UIColor.white
    })

    /// 포인트 컬러 위에 올라가는 글자/아이콘 색.
    static let appOnAccent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(white: 0.11, alpha: 1)
    })

    /// 어두운/밝은 배경 위에서 읽히는 강조 텍스트 색(카운트다운 등).
    static let appAccentText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.56, green: 0.64, blue: 1.0, alpha: 1)    // 밝은 남색
            : UIColor(white: 0.11, alpha: 1)
    })
}

/// 글래스 뒤로 비치는 컬러 배경(리퀴드 글래스 느낌을 살리려면 배경이 화려해야 함).
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    // blur(90) 4개 대신 iOS 18+ MeshGradient(GPU 네이티브) — 색 배치 동일, 화면 진입 렉 제거.
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: meshColors
        )
        .ignoresSafeArea()
    }

    // 모서리=기존 blob 색(TL·TR·BL·BR), 가운데·변=베이스. 기존 배치 그대로.
    private var meshColors: [Color] {
        if scheme == .dark {
            let base = Color.black
            return [
                Color(red: 0.11, green: 0.16, blue: 0.40), base, Color(red: 0.04, green: 0.17, blue: 0.32),
                base, Color(red: 0.03, green: 0.05, blue: 0.13), base,
                Color(red: 0.05, green: 0.23, blue: 0.27), base, Color(red: 0.16, green: 0.08, blue: 0.31)
            ]
        } else {
            let base = Color(white: 0.96)
            return [
                Color(red: 1.0, green: 0.85, blue: 0.91), base, Color(red: 0.80, green: 0.90, blue: 1.0),
                base, base, base,
                Color(red: 0.84, green: 0.96, blue: 0.89), base, Color(red: 1.0, green: 0.90, blue: 0.76)
            ]
        }
    }
}
