import SwiftUI
import SwiftData

struct AIScheduleView: View {
    @Environment(\.modelContext) private var context

    @State private var inputText = ""
    @State private var results: [ParsedEvent] = []
    @State private var editingIndex: Int?            // AI 결과 항목 직접 수정
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reply: String?                // 급식·외형 등 액션 답변
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("neisOffice") private var neisOffice = ""
    @AppStorage("neisCode") private var neisCode = ""
    @AppStorage("neisName") private var neisName = ""
    @AppStorage("neisKind") private var neisKind = ""
    @State private var speech = SpeechRecognizer()
    @FocusState private var editorFocused: Bool
    private let lang = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            inputCard
                            generateButton
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote).foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                            }
                            if let reply {
                                Text(reply)
                                    .font(.subheadline).foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .glassCard(cornerRadius: 18)
                            }
                            if !results.isEmpty { resultsSection }
                        }
                        .padding(16)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height, alignment: .top)   // 콘텐츠를 화면만큼 채워 빈 곳 어디든 탭 → 키보드 내림
                        .contentShape(Rectangle())
                        .onTapGesture { UIApplication.shared.endEditing() }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
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
            .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
                if let i = editingIndex, results.indices.contains(i) {
                    AIResultEditView(event: $results[i]).presentationDetents([.medium, .large])
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
                Button {
                    if e.action != .delete { editingIndex = idx }   // 삭제 항목은 대상이라 수정 불필요
                } label: {
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
                            if e.action == .delete && e.targetID == nil {
                                Text(lang.tr("제목이 같은 일정 전부")).font(.caption2).foregroundStyle(.secondary)
                            } else {
                                Text("\(timeText(e.start)) – \(timeText(e.end))" +
                                     (e.location.isEmpty ? "" : " · \(e.location)"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if e.action != .delete {
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        errorMessage = nil; reply = nil; results = []
        let text = inputText
        // 1) 외형(다크/라이트/시스템) 전환 — 코드로 즉시
        if let mode = detectAppearance(text) {
            appearanceRaw = mode.rawValue
            reply = lang.tr(mode.label) + " " + lang.tr("모드로 바꿨어요.")
            inputText = ""
            return
        }
        // 2) 급식 질문 — NEIS 조회해서 답변
        if text.contains("급식") {
            isLoading = true; defer { isLoading = false }
            reply = await mealReply(text)
            inputText = ""
            return
        }
        // 3) 일정 — 온디바이스 모델
        isLoading = true; defer { isLoading = false }
        do {
            let events = try await AppleIntelligenceClient()
                .generateSchedule(from: text, now: .now, existing: fetchUpcoming())
            results = events.sorted { $0.start < $1.start }
            if results.isEmpty { errorMessage = lang.tr("일정을 만들 수 없어요 — 유효한 내용을 입력해 주세요.") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "다크모드로 바꿔" 류 → 외형. 일정 제목과 헷갈리지 않게 동사가 있을 때만 인식.
    private func detectAppearance(_ t: String) -> Appearance? {
        let wants = t.contains("바꿔") || t.contains("해줘") || t.contains("모드") || t.contains("전환") || t.contains("설정")
        guard wants else { return nil }
        if t.contains("다크") || t.contains("어둡") { return .dark }
        if t.contains("라이트") || t.contains("화이트") || t.contains("밝") { return .light }
        if t.contains("시스템") || t.contains("자동") { return .system }
        return nil
    }

    /// 급식 질문 → 날짜 파싱 + NEIS 조회 + 답변 문자열.
    private func mealReply(_ text: String) async -> String {
        guard !neisCode.isEmpty else { return lang.tr("학교를 먼저 등록해 주세요 (설정 → 학생).") }
        let school = School(office: neisOffice, code: neisCode, name: neisName, kind: neisKind, address: "")
        let cal = Calendar.current
        let day: Date = text.contains("내일") ? (cal.date(byAdding: .day, value: 1, to: .now) ?? .now)
            : text.contains("모레") ? (cal.date(byAdding: .day, value: 2, to: .now) ?? .now)
            : text.contains("어제") ? (cal.date(byAdding: .day, value: -1, to: .now) ?? .now)
            : .now
        let dateStr = day.formatted(.dateTime.month().day().weekday(.short).locale(lang.locale))
        let meals = (try? await NEISClient.shared.fetchMeal(school: school, date: day)) ?? []
        guard !meals.isEmpty else { return "\(dateStr) " + lang.tr("급식 정보가 없어요") }
        let body = meals.map { m -> String in
            let menu = m.menu.split(separator: "\n").map { line -> String in
                var s = line.trimmingCharacters(in: .whitespaces)
                while s.hasPrefix("*") { s.removeFirst() }
                if let r = s.range(of: #"\s*\([0-9.\s]+\)\s*$"#, options: .regularExpression) { s.removeSubrange(r) }
                return s.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }.joined(separator: ", ")
            return "\(m.type) — \(menu)"
        }.joined(separator: "\n\n")
        return "\(dateStr)\n\(body)"
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
        var applied = 0
        for e in results {
            switch e.action {
            case .create:
                context.insert(ScheduleEvent(title: e.title, start: e.start, end: e.end, location: e.location))
                applied += 1
            case .update:
                if let t = find(e.targetID) {
                    t.title = e.title; t.start = e.start; t.end = e.end; t.location = e.location
                    applied += 1
                }
            case .delete:
                if let id = e.targetID {
                    if let t = find(id) { context.delete(t); applied += 1 }
                } else {
                    // bulk: 제목에 키워드가 든 일정을 전부 삭제(과거·미래·시간표 포함, 개수 제한 없음)
                    let all = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
                    for t in all where !e.title.isEmpty && t.title.contains(e.title) { context.delete(t); applied += 1 }
                }
            }
        }
        do {
            try context.save()
            if applied == 0 { errorMessage = lang.tr("적용할 대상을 찾지 못했어요.") }
            else { results = []; inputText = ""; errorMessage = nil }
        } catch {
            errorMessage = "저장 오류: \(error.localizedDescription)"
        }
    }

    private func find(_ id: UUID?) -> ScheduleEvent? {
        guard let id else { return nil }
        var d = FetchDescriptor<ScheduleEvent>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }
}

// AI 결과 항목을 적용 전에 직접 수정
private struct AIResultEditView: View {
    @Binding var event: ParsedEvent
    @Environment(\.dismiss) private var dismiss
    private let lang = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        field(lang.tr("제목")) {
                            TextField(lang.tr("제목"), text: $event.title).multilineTextAlignment(.trailing)
                        }
                        field(lang.tr("시작")) {
                            DatePicker("", selection: $event.start).labelsHidden()
                        }
                        field(lang.tr("종료")) {
                            DatePicker("", selection: $event.end, in: event.start...).labelsHidden()
                        }
                        field(lang.tr("장소")) {
                            TextField(lang.tr("위치"), text: $event.location).multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(16).frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(lang.tr("수정"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(lang.tr("완료")) { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassCard(cornerRadius: 18)
    }
}
