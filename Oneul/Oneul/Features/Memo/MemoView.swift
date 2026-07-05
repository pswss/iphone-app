import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 일정과 무관한 독립 메모(빠른 기록). SwiftData + CloudKit 동기화.
@Model
final class Memo {
    var id: UUID = UUID()
    var title: String = ""
    var text: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String = "", text: String = "") {
        self.title = title
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// 내보내기용 텍스트(제목을 md 헤더로).
    func exportText(markdown: Bool) -> String {
        let head = title.isEmpty ? "" : (markdown ? "# \(title)\n\n" : "\(title)\n\n")
        return head + text
    }
    var exportName: String {
        let base = title.isEmpty ? (text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "메모") : title
        return String(base.prefix(40))
    }
}

extension UTType {
    static var markdownDoc: UTType { UTType(filenameExtension: "md") ?? .plainText }
}

/// txt/md 내보내기용 단순 텍스트 도큐먼트.
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .markdownDoc] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
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
                                        Text(memo.title.isEmpty ? (memo.text.isEmpty ? lang.tr("새 메모") : firstLine(memo.text)) : memo.title)
                                            .font(.body).bold().lineLimit(1)
                                            .foregroundStyle((memo.title.isEmpty && memo.text.isEmpty) ? .secondary : .primary)
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
            #if os(iOS)
            .toolbar {                                   // 아이폰: 탭 자체 툴바의 작성 버튼
                ToolbarItem(placement: .primaryAction) {
                    Button { addMemo() } label: { Image(systemName: "square.and.pencil") }
                }
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .oneulNewMemo)) { _ in addMemo() }   // 맥: 창 툴바 '+'
        }
    }

    private func addMemo() {
        let m = Memo(); context.insert(m); try? context.save()
    }

    private func firstLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
    }
}

/// 메모 편집 — 제목 + 본문, 변경 시 자동 저장, txt/md 내보내기.
struct MemoEditor: View {
    @Bindable var memo: Memo
    @Environment(\.modelContext) private var context
    private let lang = AppLanguage.shared
    @State private var exportTXT = false
    @State private var exportMD = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                TextField(lang.tr("제목"), text: $memo.title)
                    .font(.title2).bold().textFieldStyle(.plain)
                    .padding(.horizontal, 14).padding(.top, 12)
                    .onChange(of: memo.title) { _, _ in touch() }
                Divider().padding(.horizontal, 14).padding(.top, 6)
                TextEditor(text: $memo.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .onChange(of: memo.text) { _, _ in touch() }
            }
        }
        .navigationTitle(memo.title.isEmpty ? lang.tr("메모") : memo.title)
        .navBarInline()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(lang.tr("텍스트(.txt)로 내보내기")) { exportTXT = true }
                    Button(lang.tr("마크다운(.md)으로 내보내기")) { exportMD = true }
                } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .fileExporter(isPresented: $exportTXT,
                      document: TextFileDocument(text: memo.exportText(markdown: false)),
                      contentType: .plainText, defaultFilename: memo.exportName) { _ in }
        .fileExporter(isPresented: $exportMD,
                      document: TextFileDocument(text: memo.exportText(markdown: true)),
                      contentType: .markdownDoc, defaultFilename: memo.exportName) { _ in }
    }

    private func touch() { memo.updatedAt = .now; try? context.save() }
}
