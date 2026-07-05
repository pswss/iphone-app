import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import QuickLook
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 일정과 무관한 독립 메모(빠른 기록). SwiftData + CloudKit 동기화.
@Model
final class Memo {
    var id: UUID = UUID()
    var title: String = ""
    var text: String = ""              // 평문(목록 미리보기·검색·내보내기용, 리치 내용과 동기화)
    var contentData: Data = Data()     // 리치 텍스트(AttributedString 아카이브) — CloudKit 안전한 Data
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // 첨부(사진·파일). CloudKit 동기화 위해 관계는 옵셔널, 메모 삭제 시 함께 삭제.
    @Relationship(deleteRule: .cascade, inverse: \MemoAttachment.memo)
    var attachments: [MemoAttachment]? = []

    init(title: String = "", text: String = "") {
        self.title = title
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// 저장된 리치 텍스트 로드(없으면 평문에서).
    func loadRich() -> AttributedString {
        if !contentData.isEmpty, let r = try? JSONDecoder().decode(AttributedString.self, from: contentData) { return r }
        return AttributedString(text)
    }
    /// 리치 텍스트 저장 + 평문 동기화.
    func saveRich(_ rich: AttributedString) {
        contentData = (try? JSONEncoder().encode(rich)) ?? Data()
        text = String(rich.characters)
        updatedAt = .now
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

/// 메모 첨부(사진·파일). CloudKit 동기화를 위해 관계는 옵셔널, 바이너리는 Data로 저장.
@Model
final class MemoAttachment {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var data: Data = Data()   // 원본은 외부 파일로 — 스토어 비대·CloudKit 부담 방지
    var filename: String = ""
    var typeIdentifier: String = ""   // UTType.identifier
    var createdAt: Date = Date()
    var memo: Memo?

    init(data: Data, filename: String, typeIdentifier: String) {
        self.data = data
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.createdAt = .now
    }

    var utType: UTType { UTType(typeIdentifier) ?? .data }
    var isImage: Bool { utType.conforms(to: .image) }

    /// 미리보기용 임시 파일로 써서 URL 반환(QuickLook용).
    func writeTempFile() -> URL? {
        let ext = utType.preferredFilenameExtension ?? (filename as NSString).pathExtension
        let base = filename.isEmpty ? id.uuidString : (filename as NSString).deletingPathExtension
        let name = ext.isEmpty ? base : "\(base).\(ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch { return nil }
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
    @State private var path: [Memo] = []       // 작성 버튼 → 새 메모로 즉시 이동
    @State private var search = ""
    @State private var deletedBackup: [MemoBackup] = []   // 실행 취소용 스냅샷
    @State private var undoDismissTask: Task<Void, Never>?

    private var filtered: [Memo] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return memos }
        return memos.filter { $0.title.localizedStandardContains(q) || $0.text.localizedStandardContains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
                            ForEach(filtered) { memo in
                                NavigationLink(value: memo) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(memo.title.isEmpty ? (memo.text.isEmpty ? lang.tr("새 메모") : firstLine(memo.text)) : memo.title)
                                            .font(.body).bold().lineLimit(1)
                                            .foregroundStyle((memo.title.isEmpty && memo.text.isEmpty) ? .secondary : .primary)
                                        if !memo.title.isEmpty, !memo.text.isEmpty {   // 제목 있으면 본문 첫 줄 미리보기
                                            Text(firstLine(memo.text)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        HStack(spacing: 4) {
                                            Text(memo.updatedAt, format: .dateTime.month().day().hour().minute().locale(lang.locale))
                                            if !(memo.attachments ?? []).isEmpty { Image(systemName: "paperclip") }
                                        }
                                        .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .onDelete { idx in
                                let victims = idx.map { filtered[$0] }
                                deletedBackup = victims.map { MemoBackup($0) }   // 복원용 스냅샷
                                victims.forEach(context.delete)
                                try? context.save()
                                undoDismissTask?.cancel()
                                undoDismissTask = Task {                          // 6초 뒤 스낵바 자동 닫힘
                                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                                    if !Task.isCancelled { deletedBackup = [] }
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(lang.tr("메모"))
            .navBarInline()
            .overlay(alignment: .bottom) { undoSnackbar }
            .animation(.snappy(duration: 0.25), value: deletedBackup.isEmpty)
            .navigationDestination(for: Memo.self) { MemoEditor(memo: $0) }
            .searchable(text: $search, prompt: lang.tr("메모 검색"))
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

    // 삭제 직후 실행 취소 스낵바 — 실수 스와이프 한 번에 긴 메모를 잃지 않게
    @ViewBuilder private var undoSnackbar: some View {
        if !deletedBackup.isEmpty {
            HStack(spacing: 12) {
                Text(String(format: lang.tr("메모 %d개 삭제됨"), deletedBackup.count)).font(.subheadline)
                Button(lang.tr("실행 취소")) {
                    for b in deletedBackup { b.restore(into: context) }
                    try? context.save()
                    deletedBackup = []
                    undoDismissTask?.cancel()
                }
                .font(.subheadline.bold())
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func addMemo() {
        let m = Memo(); context.insert(m); try? context.save()
        path.append(m)                          // 애플 메모처럼 바로 편집기 진입
    }

    private func firstLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
    }
}

/// 삭제 실행 취소용 스냅샷 — cascade로 함께 지워지는 첨부까지 복원.
struct MemoBackup {
    let title: String
    let text: String
    let contentData: Data
    let createdAt: Date
    let attachments: [(data: Data, filename: String, typeIdentifier: String)]

    init(_ m: Memo) {
        title = m.title; text = m.text; contentData = m.contentData; createdAt = m.createdAt
        attachments = (m.attachments ?? []).map { ($0.data, $0.filename, $0.typeIdentifier) }
    }

    func restore(into context: ModelContext) {
        let m = Memo(title: title, text: text)
        m.contentData = contentData
        m.createdAt = createdAt
        context.insert(m)
        for a in attachments {
            let att = MemoAttachment(data: a.data, filename: a.filename, typeIdentifier: a.typeIdentifier)
            att.memo = m
            context.insert(att)
            if m.attachments == nil { m.attachments = [] }
            m.attachments?.append(att)
        }
    }
}

/// 메모 편집 — 제목 + 리치 본문(애플 메모식 제목/소제목/본문 단락 스타일), 자동 저장, txt/md 내보내기.
struct MemoEditor: View {
    @Bindable var memo: Memo
    @Environment(\.modelContext) private var context
    private let lang = AppLanguage.shared
    @State private var exportTXT = false
    @State private var exportMD = false
    @State private var rich = AttributedString()
    @State private var selection = AttributedTextSelection()
    @State private var saveTask: Task<Void, Never>?      // 자동저장 디바운스
    @State private var loadedOnce = false                // onAppear 로드가 onChange를 오염시키지 않게
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var importFiles = false
    @State private var previewURL: URL?

    // 애플 메모식 단락 스타일 프리셋.
    private static let titleFont   = Font.system(size: 26, weight: .bold)
    private static let headingFont = Font.system(size: 20, weight: .bold)
    private static let subheadFont = Font.system(size: 17, weight: .semibold)
    private static let bodyFont    = Font.system(size: 15, weight: .regular)

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                TextField(lang.tr("제목"), text: $memo.title)
                    .font(.title2).bold().textFieldStyle(.plain)
                    .padding(.horizontal, 14).padding(.top, 12)
                    .onChange(of: memo.title) { _, _ in touch() }
                Divider().padding(.horizontal, 14).padding(.top, 6)
                TextEditor(text: $rich, selection: $selection)   // 리치 텍스트 + 선택 영역(서식 적용용)
                    .font(Self.bodyFont)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .onChange(of: rich) { _, new in
                        guard loadedOnce else { return }             // 열람만으로 updatedAt 갱신 방지
                        saveTask?.cancel()
                        saveTask = Task {                            // 0.6초 디바운스 — 키 입력마다 전체 재인코딩 방지
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            guard !Task.isCancelled else { return }
                            memo.saveRich(new); try? context.save()
                        }
                    }
                attachmentStrip
            }
        }
        .navigationTitle(memo.title.isEmpty ? lang.tr("메모") : memo.title)
        .navBarInline()
        .onAppear {
            rich = memo.loadRich()
            DispatchQueue.main.async { loadedOnce = true }
        }
        .onDisappear {
            saveTask?.cancel()
            if !memo.isDeleted { memo.saveRich(rich); try? context.save() }   // 디바운스 잔여분 최종 저장
            // 애플 메모처럼 빈 메모는 나가는 순간 자동 삭제
            if !memo.isDeleted, memo.title.isEmpty, memo.text.isEmpty,
               (memo.attachments ?? []).isEmpty {
                context.delete(memo); try? context.save()
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $importFiles, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { importPicked($0) }
        .quickLookPreview($previewURL)
        .onChange(of: previewURL) { old, new in
            if new == nil, let old { try? FileManager.default.removeItem(at: old) }   // 미리보기 임시 사본 정리
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showPhotos = true }  label: { Label(lang.tr("사진"), systemImage: "photo") }
                    Button { importFiles = true } label: { Label(lang.tr("파일"), systemImage: "doc") }
                } label: { Image(systemName: "paperclip") }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section(lang.tr("단락 스타일")) {
                        Button { applyFont(Self.titleFont) }   label: { Label(lang.tr("제목"),   systemImage: "textformat.size.larger") }
                        Button { applyFont(Self.headingFont) } label: { Label(lang.tr("제목 2"), systemImage: "textformat") }
                        Button { applyFont(Self.subheadFont) } label: { Label(lang.tr("소제목"), systemImage: "textformat.size.smaller") }
                        Button { applyFont(Self.bodyFont) }    label: { Label(lang.tr("본문"),   systemImage: "text.alignleft") }
                    }
                    Divider()
                    Button { applyBold() }   label: { Label(lang.tr("굵게"),   systemImage: "bold") }
                        .disabled(!hasRangeSelection)
                    Button { applyItalic() } label: { Label(lang.tr("기울임"), systemImage: "italic") }
                        .disabled(!hasRangeSelection)
                } label: { Image(systemName: "textformat") }
            }
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

    // MARK: 첨부 스트립(사진·파일 미리보기 썸네일)
    @ViewBuilder private var attachmentStrip: some View {
        let atts = (memo.attachments ?? []).sorted { $0.createdAt < $1.createdAt }
        if !atts.isEmpty {
            Divider().padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(atts) { att in
                        attachmentThumb(att)
                            .onTapGesture { previewURL = att.writeTempFile() }   // 탭 → QuickLook
                            .contextMenu {
                                Button(role: .destructive) { delete(att) } label: {
                                    Label(lang.tr("삭제"), systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .frame(height: 96)
        }
    }

    private func attachmentThumb(_ att: MemoAttachment) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.gray.opacity(0.15))
                if att.isImage, let img = Self.thumbnail(att.data) {
                    img.resizable().scaledToFill()
                } else {
                    Image(systemName: Self.iconName(att.utType)).font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.primary.opacity(0.08)))
            Text(att.filename).font(.caption2).lineLimit(1).frame(width: 66)
        }
    }

    // MARK: 첨부 추가/삭제
    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ut = item.supportedContentTypes.first ?? .image
            let ext = ut.preferredFilenameExtension ?? "jpg"
            addAttachment(data: data, filename: "\(lang.tr("사진"))-\(shortStamp()).\(ext)", type: ut)
        }
        photoItems = []
    }

    private func importPicked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let ut = UTType(filenameExtension: url.pathExtension) ?? .data
            addAttachment(data: data, filename: url.lastPathComponent, type: ut)
        }
    }

    private func addAttachment(data: Data, filename: String, type: UTType) {
        let att = MemoAttachment(data: data, filename: filename, typeIdentifier: type.identifier)
        att.memo = memo
        context.insert(att)
        if memo.attachments == nil { memo.attachments = [] }
        memo.attachments?.append(att)
        touch()
    }

    private func delete(_ att: MemoAttachment) {
        memo.attachments?.removeAll { $0.id == att.id }
        context.delete(att)
        touch()
    }

    private func shortStamp() -> String { String(UUID().uuidString.prefix(6)) }

    /// 데이터 → 플랫폼 이미지 → SwiftUI Image(썸네일).
    private static func thumbnail(_ data: Data) -> Image? {
        #if canImport(UIKit)
        if let ui = UIImage(data: data) { return Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = NSImage(data: data) { return Image(nsImage: ns) }
        #endif
        return nil
    }

    private static func iconName(_ t: UTType) -> String {
        if t.conforms(to: .pdf) { return "doc.richtext" }
        if t.conforms(to: .movie) || t.conforms(to: .audiovisualContent) { return "film" }
        if t.conforms(to: .audio) { return "waveform" }
        if t.conforms(to: .text) { return "doc.text" }
        return "doc"
    }

    // MARK: 서식 적용
    /// 단락 스타일 — 선택 범위가 있으면 그 범위, 캐럿만 있으면 캐럿이 놓인 문단 전체(애플 메모식).
    private func applyFont(_ font: Font) {
        if case .insertionPoint(let idx) = selection.indices(in: rich) {
            let r = paragraphRange(around: idx)
            guard !r.isEmpty else { return }
            rich[r].font = font
        } else {
            rich.transformAttributes(in: &selection) { $0.font = font }
        }
        persist()
    }

    /// idx가 속한 문단(양쪽 개행 사이) 범위.
    private func paragraphRange(around idx: AttributedString.Index) -> Range<AttributedString.Index> {
        let chars = rich.characters
        var lo = idx, hi = idx
        while lo > chars.startIndex {
            let p = chars.index(before: lo)
            if chars[p] == "\n" { break }
            lo = p
        }
        while hi < chars.endIndex, chars[hi] != "\n" { hi = chars.index(after: hi) }
        return lo..<hi
    }

    /// 굵게/기울임은 범위 선택이 있을 때만 의미 있음(캐럿뿐이면 메뉴 비활성).
    private var hasRangeSelection: Bool {
        if case .insertionPoint = selection.indices(in: rich) { return false }
        return true
    }
    private func applyBold() {
        rich.transformAttributes(in: &selection) { $0.font = ($0.font ?? Self.bodyFont).bold() }
        persist()
    }
    private func applyItalic() {
        rich.transformAttributes(in: &selection) { $0.font = ($0.font ?? Self.bodyFont).italic() }
        persist()
    }
    private func persist() { memo.saveRich(rich); try? context.save() }

    private func touch() { memo.updatedAt = .now; try? context.save() }
}
