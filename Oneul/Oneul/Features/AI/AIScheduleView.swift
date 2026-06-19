import SwiftUI
import SwiftData

struct AIScheduleView: View {
    @Environment(\.modelContext) private var context

    @State private var inputText = ""
    @State private var results: [ParsedEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var speech = SpeechRecognizer()
    @FocusState private var editorFocused: Bool
    private let lang = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        inputCard
                        generateButton
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote).foregroundStyle(.red)
                                .padding(.horizontal, 4)
                        }
                        if !results.isEmpty { resultsSection }
                    }
                    .padding(16)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { UIApplication.shared.endEditing() }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Apple Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .task { AppleIntelligenceClient.prewarm() }
            .onChange(of: speech.transcript) { _, t in if !t.isEmpty { inputText = t } }
            .onDisappear { speech.stop() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(lang.tr("완료")) { editorFocused = false }
                }
            }
        }
    }

    private var inputCard: some View {
        ZStack(alignment: .topLeading) {
            if inputText.isEmpty {
                Text(lang.tr("예: 내일 9시 팀 회의 추가, 금요일 약속 취소, 점심 1시로 옮겨줘"))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $inputText)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(8)
        }
        .glassCard(cornerRadius: 20)
        .overlay(alignment: .bottomTrailing) {
            Button {
                editorFocused = false
                speech.toggle()
            } label: {
                Image(systemName: speech.isRecording ? "mic.fill" : "mic")
                    .font(.headline)
                    .foregroundStyle(speech.isRecording ? .red : Color.appAccentText)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    private var canGenerate: Bool {
        !isLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var generateButton: some View {
        let active = canGenerate || isLoading
        return Button {
            editorFocused = false
            Task { await generate() }
        } label: {
            Group {
                if isLoading { ProgressView().tint(.white) }
                else { Image(systemName: "arrow.up").font(.title2.weight(.bold)) }
            }
            .foregroundStyle(canGenerate ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(active ? Color.blue : Color.gray.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(active ? 0.25 : 0), lineWidth: 1)
            )
            .shadow(color: active ? Color.blue.opacity(0.55) : .clear, radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
        .animation(.easeInOut(duration: 0.2), value: canGenerate)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(lang.isEnglish ? "\(results.count) items" : "AI 결과 · \(results.count)개")
                .font(.caption).bold().foregroundStyle(.secondary).padding(.leading, 4)

            ForEach(Array(results.enumerated()), id: \.element.id) { idx, e in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(EventPalette.color(idx)).frame(width: 4)
                    Text(timeText(e.start))
                        .font(.caption).bold().foregroundStyle(.secondary).frame(width: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(e.title).font(.subheadline).bold()
                            if e.action != .create {
                                Text(e.action == .delete ? lang.tr("삭제") : lang.tr("수정"))
                                    .font(.caption2).bold().foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(e.action == .delete ? Color.red : Color.orange, in: Capsule())
                            }
                        }
                        Text("\(timeText(e.start)) – \(timeText(e.end))" +
                             (e.location.isEmpty ? "" : " · \(e.location)"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .glassCard(cornerRadius: 18)
            }

            Button(lang.tr("적용하기"), action: addAll)
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 4)
        }
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().locale(lang.locale))
    }

    private func generate() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let events = try await AppleIntelligenceClient()
                .generateSchedule(from: inputText, now: .now, existing: fetchUpcoming())
            results = events.sorted { $0.start < $1.start }
            if results.isEmpty { errorMessage = lang.tr("일정을 만들 수 없어요 — 유효한 내용을 입력해 주세요.") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 수정/삭제 대상이 될 다가오는 일정(최대 25개).
    private func fetchUpcoming() -> [ExistingEvent] {
        let now = Date()
        var d = FetchDescriptor<ScheduleEvent>(
            predicate: #Predicate { $0.start >= now }, sortBy: [SortDescriptor(\.start)])
        d.fetchLimit = 25
        let items = (try? context.fetch(d)) ?? []
        return items.map { ExistingEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, location: $0.location) }
    }

    private func addAll() {
        for e in results {
            switch e.action {
            case .create:
                context.insert(ScheduleEvent(title: e.title, start: e.start, end: e.end, location: e.location))
            case .update:
                if let t = find(e.targetID) {
                    t.title = e.title; t.start = e.start; t.end = e.end; t.location = e.location
                }
            case .delete:
                if let t = find(e.targetID) { context.delete(t) }
            }
        }
        try? context.save()
        results = []
        inputText = ""
    }

    private func find(_ id: UUID?) -> ScheduleEvent? {
        guard let id else { return nil }
        var d = FetchDescriptor<ScheduleEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
}
