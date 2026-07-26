import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension Color {
    /// 라이트/다크 동적 색 (iOS=UIColor 트레이트, macOS=NSColor appearance).
    private static func dynamic(light: (Double, Double, Double, Double),
                                dark: (Double, Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
            : UIColor(red: light.0, green: light.1, blue: light.2, alpha: light.3) })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { ap in
            let d = ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: d.0, green: d.1, blue: d.2, alpha: d.3)
        })
        #else
        return .accentColor
        #endif
    }

    /// 앱 포인트 컬러 — 라이트=화이트, 다크=남색.
    static let appAccent = dynamic(light: (1, 1, 1, 1), dark: (0.18, 0.29, 0.63, 1))
    /// 포인트 컬러 위에 올라가는 글자/아이콘 색.
    static let appOnAccent = dynamic(light: (0.11, 0.11, 0.11, 1), dark: (1, 1, 1, 1))
    /// 어두운/밝은 배경 위에서 읽히는 강조 텍스트 색(카운트다운 등).
    static let appAccentText = dynamic(light: (0.11, 0.11, 0.11, 1), dark: (0.56, 0.64, 1.0, 1))

    /// 시스템 배경색 (iOS=.systemBackground, macOS=.windowBackgroundColor).
    static var appSystemBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.white
        #endif
    }
}

/// 글래스 뒤로 비치는 컬러 배경(리퀴드 글래스 느낌을 살리려면 배경이 화려해야 함).
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    // blur(90) 4개 대신 iOS 18+ MeshGradient(GPU 네이티브) — 색 배치 동일, 화면 진입 렉 제거.
    var body: some View {
        if reduceTransparency || contrast == .increased {
            Rectangle().fill(Color.appSystemBackground).ignoresSafeArea()
        } else {
            #if os(macOS)
            Rectangle().fill(.background).ignoresSafeArea()   // 앱 외형(시스템/라이트/다크)을 따르는 배경 — 시스템 전환 시 혼합 방지
            #else
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
            #endif
        }
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
