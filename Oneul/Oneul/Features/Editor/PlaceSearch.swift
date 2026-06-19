import SwiftUI
import MapKit
import CoreLocation

/// MapKit 자동완성 검색.
final class PlaceCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address]
        completer.delegate = self
    }

    func search(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { results = []; return }
        completer.queryFragment = t
    }

    func completerDidUpdateResults(_ c: MKLocalSearchCompleter) { results = c.results }
    func completer(_ c: MKLocalSearchCompleter, didFailWithError error: Error) { results = [] }
}

/// 현재 위치 1회 조회 → 장소명.
final class LocationOneShot: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var busy = false
    private let manager = CLLocationManager()
    private var done: ((String?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetch(_ completion: @escaping (String?) -> Void) {
        done = completion
        busy = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if busy, m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
            m.requestLocation()
        } else if busy, m.authorizationStatus == .denied || m.authorizationStatus == .restricted {
            finish(nil)
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { return finish(nil) }
        Task { self.finish(await Self.placeName(for: loc)) }
    }

    /// iOS 26: CLGeocoder(deprecated) 대신 MapKit 역지오코딩.
    private static func placeName(for loc: CLLocation) async -> String {
        guard let request = MKReverseGeocodingRequest(location: loc) else { return "현재 위치" }
        let items = try? await request.mapItems
        return items?.first?.name ?? "현재 위치"
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) { finish(nil) }

    private func finish(_ s: String?) {
        DispatchQueue.main.async { self.busy = false; self.done?(s); self.done = nil }
    }
}

/// 장소 검색 시트 — 현재 위치 + 실제 장소 검색.
struct PlaceSearchSheet: View {
    @Binding var location: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var completer = PlaceCompleter()
    @StateObject private var loc = LocationOneShot()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Button {
                    loc.fetch { name in if let name { location = name; dismiss() } }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.fill").foregroundStyle(.blue)
                        Text("현재 위치 사용")
                        Spacer()
                        if loc.busy { ProgressView() }
                    }
                }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Button {
                            location = query; dismiss()
                        } label: {
                            Label("\"\(query)\" 직접 입력", systemImage: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ForEach(completer.results, id: \.self) { r in
                    Button {
                        location = r.title; dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).foregroundStyle(.primary)
                            if !r.subtitle.isEmpty {
                                Text(r.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "장소 검색")
            .onChange(of: query) { _, q in completer.search(q) }
            .navigationTitle("장소")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } }
        }
    }
}
