import SwiftUI
import MapKit

#if canImport(NMapsMap)
import NMapsMap

/// 네이버 네이티브 지도(앱 내 임베드). 장소 이름을 좌표로 변환해 핀 표시.
/// 사용하려면: ① Xcode에서 SPM 패키지 https://github.com/navermaps/SPM-NMapsMap 추가,
///            ② Info.plist에 NMFNcpKeyId(NCP Client ID) 설정.
struct NaverMapView: UIViewRepresentable {
    let place: String

    func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView()
        view.showZoomControls = false
        view.showLocationButton = true
        return view
    }

    func updateUIView(_ uiView: NMFNaverMapView, context: Context) {
        let place = self.place
        Task { @MainActor in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = place
            guard let c = try? await MKLocalSearch(request: request).start().mapItems.first?.placemark.coordinate else { return }
            let pos = NMGLatLng(lat: c.latitude, lng: c.longitude)
            uiView.mapView.moveCamera(NMFCameraUpdate(scrollTo: pos, zoomTo: 15))
            let marker = NMFMarker(position: pos)
            marker.mapView = uiView.mapView
        }
    }
}
#else
/// 네이버 지도 SDK가 추가되기 전 자리표시(SPM 패키지 + 키 추가 시 실제 지도로 동작).
struct NaverMapView: View {
    let place: String
    var body: some View {
        ZStack {
            Color.gray.opacity(0.15)
            VStack(spacing: 8) {
                Image(systemName: "map").font(.largeTitle).foregroundStyle(.secondary)
                Text("네이버 지도 SDK를 추가하면\n여기에 지도가 표시됩니다")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding()
        }
    }
}
#endif
