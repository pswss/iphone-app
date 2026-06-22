import UIKit
import MapKit

/// 네이버 지도 앱으로 길찾기/검색을 연다(URL 스킴 — 키·SDK 불필요).
/// 장소 이름을 좌표로 변환(MKLocalSearch)해 길찾기, 실패하면 검색. 미설치면 App Store로.
enum MapDirections {
    private static let appName = "com.oneul.app"
    private static let appStore = "https://apps.apple.com/app/id311867728"   // 네이버 지도

    static func open(to place: String) {
        let name = place.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task { @MainActor in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = name
            let coord = try? await MKLocalSearch(request: request).start().mapItems.first?.location.coordinate
            let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
            let str = coord.map { "nmap://route/car?dlat=\($0.latitude)&dlng=\($0.longitude)&dname=\(q)&appname=\(appName)" }
                ?? "nmap://search?query=\(q)&appname=\(appName)"
            if let url = URL(string: str), UIApplication.shared.canOpenURL(url) {
                _ = await UIApplication.shared.open(url)
            } else if let store = URL(string: appStore) {
                _ = await UIApplication.shared.open(store)   // 네이버 지도 미설치
            }
        }
    }
}
