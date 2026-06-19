import SwiftUI
import SwiftData

struct AIScheduleView: View {
    @Environment(\.modelContext) private var context

    @State private var inputText = ""
    @State private var results: [ParsedEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var editorFocused: Bool
    private let lang = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        infoLabel
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
            .navigationTitle(lang.tr("일정 생성"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(lang.tr("완료")) { editorFocused = false }
                }
            }
        }
    }

    private var infoLabel: some View {
        Label("Apple Intelligence · 온디바이스 (키 불필요)", systemImage: "apple.logo")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private var inputCard: some View {
        ZStack(alignment: .topLeading) {
            if inputText.isEmpty {
                Text(lang.tr("예: 내일 오전 9시 팀 회의, 12시 반 점심, 3시에 헬스장 1시간, 저녁 7시 친구 약속"))
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
    }

    private var canGenerate: Bool {
        !isLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var generateButton: some View {
        Button {
            editorFocused = false
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(.white) }
                Text(isLoading ? lang.tr("생성 중...") : lang.tr("일정 생성"))
                    .font(.headline)
            }
            .foregroundStyle(canGenerate ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(canGenerate ? Color.blue : Color.gray.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(canGenerate ? 0.25 : 0), lineWidth: 1)
            )
            .shadow(color: canGenerate ? Color.blue.opacity(0.55) : .clear, radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
        .animation(.easeInOut(duration: 0.2), value: canGenerate)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(lang.isEnglish ? "\(results.count) events" : "생성된 일정 · \(results.count)개")
                .font(.caption).bold().foregroundStyle(.secondary).padding(.leading, 4)

            ForEach(Array(results.enumerated()), id: \.element.id) { idx, e in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(EventPalette.color(idx)).frame(width: 4)
                    Text(timeText(e.start))
                        .font(.caption).bold().foregroundStyle(.secondary).frame(width: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.subheadline).bold()
                        Text("\(timeText(e.start)) – \(timeText(e.end))" +
                             (e.location.isEmpty ? "" : " · \(e.location)"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .glassCard(cornerRadius: 18)
            }

            Button(lang.tr("＋ 전체 일정에 추가"), action: addAll)
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
            let events = try await AppleIntelligenceClient().generateSchedule(from: inputText)
            results = events.sorted { $0.start < $1.start }
            if results.isEmpty { errorMessage = lang.tr("일정을 찾지 못했어요. 더 구체적으로 적어 보세요.") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addAll() {
        for e in results {
            context.insert(ScheduleEvent(title: e.title, start: e.start, end: e.end, location: e.location))
        }
        try? context.save()
        results = []
        inputText = ""
    }
}
