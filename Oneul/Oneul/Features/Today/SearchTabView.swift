#if os(iOS)
import SwiftUI
import SwiftData

/// 플로팅 일정 검색 — 검색 탭을 누르면 탭바에서 검색이 사라지고,
/// 현재 탭 위쪽에 이 검색창이 떠오른다. 완료/취소하면 탭이 되돌아온다.
struct FloatingSearchOverlay: View {
    var onPick: (Date) -> Void
    var onDismiss: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var loading = true
    @State private var loadFailed = false
    @FocusState private var focused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    private let lang = AppLanguage.shared

    /// 검색용 경량 사본 — 전체 SwiftData 오브젝트를 메인에서 동기 로드하던 첫 오픈 렉 제거.
    private struct Lite: Identifiable, Sendable { let id: UUID; let title: String; let location: String; let start: Date }
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
        loading = true
        loadFailed = false
        let container = context.container
        Task.detached(priority: .userInitiated) {
            let ctx = ModelContext(container)
            do {
                let all = try ctx.fetch(FetchDescriptor<ScheduleEvent>())
                let lite = all.map { Lite(id: $0.id, title: $0.title, location: $0.location, start: $0.start) }
                await MainActor.run {
                    items = lite
                    loading = false
                }
            } catch {
                await MainActor.run {
                    items = []
                    loadFailed = true
                    loading = false
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.subheadline).foregroundStyle(.secondary)
                TextField(lang.tr("제목이나 장소"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .accessibilityFocused($accessibilityFocused)
                    .submitLabel(.search)
                    .onSubmit { if let f = results.first { pick(f) } }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.body).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel(lang.tr("닫기"))
            }
            .padding(.leading, 14).padding(.trailing, 4)
            .glassEffect(.regular, in: Capsule())

            if loading {
                ProgressView()
                    .accessibilityLabel(lang.tr("일정을 불러오는 중…"))
                    .padding(.vertical, 10)
            } else if loadFailed {
                VStack(spacing: 8) {
                    Text(lang.tr("일정을 불러오지 못했어요. 잠시 후 다시 시도해 주세요."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(lang.tr("다시 시도"), action: loadItems)
                        .font(.caption.bold())
                        .frame(minWidth: 44, minHeight: 44)
                }
                .padding(12)
                .glassCard(cornerRadius: 18)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty && results.isEmpty {
                Text(lang.tr("검색 결과가 없어요"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else if !results.isEmpty {
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
                            .frame(minHeight: 44)
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
        .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
        .onAppear {
            focused = true
            DispatchQueue.main.async { accessibilityFocused = true }
            loadItems()
        }
    }

    private func pick(_ e: Lite) {
        onPick(e.start)
        dismiss()
    }
    private func dismiss() {
        focused = false
        accessibilityFocused = false
        if reduceMotion { onDismiss() }
        else { withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { onDismiss() } }
    }
}
#endif
