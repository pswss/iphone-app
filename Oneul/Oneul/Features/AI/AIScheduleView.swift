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
    @State private var micPulse = false              // 녹음 중 펄스 애니메이션
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
                                    .font(.body).foregroundStyle(.primary)
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                                    .padding(18)
                                    .glassCard(cornerRadius: 20)
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
                Text(lang.tr("예: 매주 월요일 7시 영어학원 · 다음주 월요일 급식 · 내일 뭐 있어? · 다크모드로 바꿔줘"))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $inputText)
                .focused($editorFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 68)
                .padding(8)
        }
        .glassCard(cornerRadius: 20)
        .overlay(alignment: .bottomTrailing) { micButton }
    }

    /// 애플 키보드 마이크처럼 토글 + 녹음 중 펄스 애니메이션.
    private var micButton: some View {
        Button {
            editorFocused = false
            speech.toggle()
        } label: {
            Image(systemName: "mic.fill")
                .font(.headline)
                .foregroundStyle(speech.isRecording ? .white : Color.appAccentText)
                .frame(width: 40, height: 40)
                .background {
                    ZStack {
                        if speech.isRecording {   // 퍼지며 사라지는 펄스 링
                            Circle().stroke(Color.red.opacity(0.6), lineWidth: 2)
                                .scaleEffect(micPulse ? 1.75 : 1.0)
                                .opacity(micPulse ? 0 : 0.85)
                        }
                        Circle().fill(speech.isRecording ? Color.red : Color.clear)
                        Circle().fill(.ultraThinMaterial).opacity(speech.isRecording ? 0 : 1)
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(speech.isRecording ? 0.3 : 0.15)))
                .scaleEffect(speech.isRecording ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: speech.isRecording)
        }
        .buttonStyle(.plain)
        .padding(10)
        .onChange(of: speech.isRecording) { _, recording in
            if recording {
                micPulse = false
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { micPulse = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { micPulse = false }
            }
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
                                if e.recurrence != .none {
                                    Text(repeatLabel(e))
                                        .font(.caption2).bold().foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.blue, in: Capsule())
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

    /// 반복 배지 문구: "매주" 또는 "매주 월수금".
    private func repeatLabel(_ e: ParsedEvent) -> String {
        guard e.recurrence != .none else { return "" }
        if e.recurrence == .weekly && !e.weekdays.isEmpty {
            let syms = ["일", "월", "화", "수", "목", "금", "토"]
            let days = e.weekdays.sorted().compactMap { (1...7).contains($0) ? syms[$0 - 1] : nil }.joined()
            return lang.tr(e.recurrence.label) + " " + days
        }
        return lang.tr(e.recurrence.label)
    }

    private func generate() async {
        errorMessage = nil; reply = nil; results = []
        let text = inputText
        isLoading = true; defer { isLoading = false }
        do {
            let result = try await AppleIntelligenceClient()
                .generateSchedule(from: text, now: .now, existing: fetchUpcoming())

            // 즉시 액션(외형/급식/일정 질문) 처리 → 답변 모음
            var replies: [String] = []
            for action in result.actions {
                switch action {
                case .setAppearance(let mode):
                    appearanceRaw = mode.rawValue
                    replies.append(lang.tr(mode.label) + " " + lang.tr("모드로 바꿨어요."))
                case .mealQuery(let date):
                    replies.append(await mealReply(date: date))
                case .scheduleQuery(let kind, let day):
                    replies.append(scheduleQueryReply(kind: kind, day: day))
                case .unknown:
                    break
                }
            }

            results = result.events.sorted { $0.start < $1.start }
            if !replies.isEmpty { reply = replies.joined(separator: "\n\n") }

            if result.isEmpty {
                errorMessage = lang.tr("무엇을 할지 이해하지 못했어요. 다시 말해 주세요.")
            } else {
                inputText = ""   // 처리됨(미리보기는 results로, 답변은 reply로)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 급식 질문 → 해석된 날짜로 NEIS 조회 + 답변 문자열.
    private func mealReply(date day: Date) async -> String {
        guard !neisCode.isEmpty else { return lang.tr("학교를 먼저 등록해 주세요 (설정 → 학생).") }
        let school = School(office: neisOffice, code: neisCode, name: neisName, kind: neisKind, address: "")
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

    /// 일정·시험 질문 → 저장된 일정 조회 + 텍스트 답변.
    private func scheduleQueryReply(kind: AIQueryKind, day: Date) -> String {
        let cal = Calendar.current
        switch kind {
        case .exam:
            let now = Date()
            var d = FetchDescriptor<ScheduleEvent>(
                predicate: #Predicate { $0.start >= now }, sortBy: [SortDescriptor(\.start)])
            d.fetchLimit = 200
            let items = (try? context.fetch(d)) ?? []
            guard let next = items.first(where: { $0.examKind.isExam }) else {
                return lang.tr("다가오는 시험이 없어요.")
            }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now),
                                          to: cal.startOfDay(for: next.start)).day ?? 0
            let dleft = days <= 0 ? "D-DAY" : "D-\(days)"
            let ds = next.start.formatted(.dateTime.month().day().locale(lang.locale))
            return "\(next.title) · \(ds) (\(dleft))"
        case .day:
            let from = cal.startOfDay(for: day)
            let to = cal.date(byAdding: .day, value: 1, to: from) ?? from
            let label = day.formatted(.dateTime.month().day().weekday(.short).locale(lang.locale))
            return eventsReply(from: from, to: to, label: label)
        case .week:
            let todayWd = cal.component(.weekday, from: day)
            let monday = cal.date(byAdding: .day, value: -((todayWd + 5) % 7), to: cal.startOfDay(for: day)) ?? day
            let to = cal.date(byAdding: .day, value: 7, to: monday) ?? day
            let label = monday.formatted(.dateTime.month().day().locale(lang.locale)) + " " + lang.tr("주")
            return eventsReply(from: monday, to: to, label: label)
        }
    }

    private func eventsReply(from: Date, to: Date, label: String) -> String {
        var d = FetchDescriptor<ScheduleEvent>(
            predicate: #Predicate { $0.start >= from && $0.start < to }, sortBy: [SortDescriptor(\.start)])
        d.fetchLimit = 50
        let items = (try? context.fetch(d)) ?? []
        guard !items.isEmpty else { return "\(label) " + lang.tr("일정이 없어요.") }
        let body = items.prefix(20).map { e in
            "\(e.start.formatted(.dateTime.month().day().hour().minute().locale(lang.locale))) \(e.title)"
        }.joined(separator: "\n")
        return "\(label)\n\(body)"
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
                EventActions.create(title: e.title, start: e.start, end: e.end, location: e.location,
                                    reminderMinutes: 10, recurrence: e.recurrence,
                                    weekdays: e.weekdays, endDate: e.endDate, into: context)
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

    private var repeatText: String {
        if event.recurrence == .weekly && !event.weekdays.isEmpty {
            let syms = ["일", "월", "화", "수", "목", "금", "토"]
            let days = event.weekdays.sorted().compactMap { (1...7).contains($0) ? syms[$0 - 1] : nil }.joined()
            return lang.tr(event.recurrence.label) + " " + days
        }
        return lang.tr(event.recurrence.label)
    }

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
                        if event.recurrence != .none {
                            field(lang.tr("반복")) {
                                Text(repeatText).foregroundStyle(.secondary)
                            }
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
