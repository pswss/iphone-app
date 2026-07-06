#if os(iOS)
import SwiftUI
import SwiftData

/// 플로팅 일정 검색 — 검색 탭을 누르면 탭바에서 검색이 사라지고,
/// 현재 탭 위쪽에 이 검색창이 떠오른다. 완료/취소하면 탭이 되돌아온다.
struct FloatingSearchOverlay: View {
    var onPick: (Date) -> Void
    var onDismiss: () -> Void
    @Query(sort: \ScheduleEvent.start) private var events: [ScheduleEvent]
    @State private var query = ""
    @FocusState private var focused: Bool
    private let lang = AppLanguage.shared

    private var results: [ScheduleEvent] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(events
            .filter { $0.title.localizedStandardContains(q) || $0.location.localizedStandardContains(q) }
            .sorted { abs($0.start.timeIntervalSinceNow) < abs($1.start.timeIntervalSinceNow) }
            .prefix(8))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.subheadline).foregroundStyle(.secondary)
                TextField(lang.tr("제목이나 장소"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { if let f = results.first { pick(f) } }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .glassEffect(.regular, in: Capsule())

            if !results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { i, e in
                        Button { pick(e) } label: {
                            HStack(spacing: 8) {
                                Text(e.title.isEmpty ? lang.tr("제목 없음") : e.title)
                                    .font(.subheadline).bold().lineLimit(1)
                                Spacer(minLength: 6)
                                Text(e.start, format: .dateTime.month().day().weekday(.abbreviated).locale(lang.locale))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < results.count - 1 { Divider().padding(.horizontal, 12) }
                    }
                }
                .glassCard(cornerRadius: 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear { focused = true }
    }

    private func pick(_ e: ScheduleEvent) {
        onPick(e.start)
        dismiss()
    }
    private func dismiss() {
        focused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { onDismiss() }
    }
}
#endif
