#if os(iOS)
import SwiftUI
import SwiftData

/// 하단 검색 탭(role .search) — 애플 뮤직식 검색 필 모핑은 시스템이 제공.
/// 제목·장소로 일정을 찾고, 결과를 탭하면 오늘 탭의 그 날짜로 이동.
struct SearchTabView: View {
    var onPick: (Date) -> Void
    @Query(sort: \ScheduleEvent.start) private var events: [ScheduleEvent]
    @State private var query = ""
    private let lang = AppLanguage.shared

    private var results: [ScheduleEvent] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(events
            .filter { $0.title.localizedStandardContains(q) || $0.location.localizedStandardContains(q) }
            .sorted { abs($0.start.timeIntervalSinceNow) < abs($1.start.timeIntervalSinceNow) }   // 지금과 가까운 순
            .prefix(60))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text(lang.tr("제목이나 장소로 일정을 찾아요"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if results.isEmpty {
                    Text(lang.tr("검색 결과가 없어요"))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    List(results) { e in
                        Button { onPick(e.start) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title)
                                    .font(.body).bold().lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(e.start, format: .dateTime.year().month().day()
                                        .weekday(.abbreviated).hour().minute().locale(lang.locale))
                                    if !e.location.isEmpty { Text("· " + e.location).lineLimit(1) }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(lang.tr("검색"))
            .navBarInline()
            .searchable(text: $query, prompt: lang.tr("제목이나 장소"))
        }
    }
}
#endif
