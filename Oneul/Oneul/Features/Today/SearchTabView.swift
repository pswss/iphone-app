#if os(iOS)
import SwiftUI
import SwiftData

/// 플로팅 일정 검색 — 검색 탭을 누르면 탭바에서 검색이 사라지고,
/// 현재 탭 위쪽에 이 검색창이 떠오른다. 완료/취소하면 탭이 되돌아온다.
struct FloatingSearchOverlay: View {
    var onPick: (Date) -> Void
    var onDismiss: () -> Void
    @Environment(\.modelContext) private var context
    @State private var query = ""
    @FocusState private var focused: Bool
    private let lang = AppLanguage.shared

    /// 검색용 경량 사본 — 전체 SwiftData 오브젝트를 메인에서 동기 로드하던 첫 오픈 렉 제거.
    private struct Lite: Identifiable { let id: UUID; let title: String; let location: String; let start: Date }
    @State private var items: [Lite] = []

    private var results: [Lite] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(items
            .filter { $0.title.localizedStandardContains(q) || $0.location.localizedStandardContains(q) }
            .sorted { abs($0.start.timeIntervalSinceNow) < abs($1.start.timeIntervalSinceNow) }
            .prefix(8))
    }

    private func loadItems() {
        let container = context.container
        Task.detached(priority: .userInitiated) {
            let ctx = ModelContext(container)
            let all = (try? ctx.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
            let lite = all.map { Lite(id: $0.id, title: $0.title, location: $0.location, start: $0.start) }
            await MainActor.run { items = lite }
        }
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
        .onAppear {
            focused = true
            loadItems()
        }
    }

    private func pick(_ e: Lite) {
        onPick(e.start)
        dismiss()
    }
    private func dismiss() {
        focused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { onDismiss() }
    }
}
#endif
