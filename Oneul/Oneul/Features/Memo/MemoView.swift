import SwiftUI
import SwiftData

/// 일정과 무관한 독립 메모(빠른 기록). SwiftData + CloudKit 동기화.
@Model
final class Memo {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(text: String = "") {
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
    }
}

/// 메모 목록 + 편집. 사이드바(맥)/탭(아이폰) 한 섹션.
struct MemoView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Memo.updatedAt, order: .reverse) private var memos: [Memo]
    private let lang = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                Group {
                    if memos.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "note.text").font(.largeTitle).foregroundStyle(.secondary)
                            Text(lang.tr("메모가 없어요")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        List {
                            ForEach(memos) { memo in
                                NavigationLink {
                                    MemoEditor(memo: memo)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(memo.text.isEmpty ? lang.tr("새 메모") : firstLine(memo.text))
                                            .font(.body).lineLimit(1)
                                            .foregroundStyle(memo.text.isEmpty ? .secondary : .primary)
                                        Text(memo.updatedAt, format: .dateTime.month().day().hour().minute().locale(lang.locale))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .onDelete { idx in
                                idx.map { memos[$0] }.forEach(context.delete)
                                try? context.save()
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(lang.tr("메모"))
            .navBarInline()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let m = Memo(); context.insert(m); try? context.save()
                    } label: { Image(systemName: "square.and.pencil") }
                }
            }
        }
    }

    private func firstLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
    }
}

/// 메모 편집 — TextEditor, 변경 시 자동 저장.
struct MemoEditor: View {
    @Bindable var memo: Memo
    @Environment(\.modelContext) private var context
    private let lang = AppLanguage.shared

    var body: some View {
        ZStack {
            AppBackground()
            TextEditor(text: $memo.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .onChange(of: memo.text) { _, _ in
                    memo.updatedAt = .now
                    try? context.save()
                }
        }
        .navigationTitle(lang.tr("메모"))
        .navBarInline()
    }
}
