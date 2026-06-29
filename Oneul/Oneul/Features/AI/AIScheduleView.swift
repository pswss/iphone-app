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
    @State private var clarifyCandidates: [DeleteCandidate] = []   // "어떤 것을 삭제할까요?" 후보
    @State private var clarifyPrompt: String?
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
                if isLoading {                                    // 처리 중일 때만 렌더(무거운 blur 4개를 idle엔 안 그림 → 진입 렉↓)
                    AIThinkingGlow().transition(.opacity)
                }
                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Works through Apple Intelligence")   // 지칭적 표기(영어 고정, 아이콘 없음)
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                            inputCard
                            generateButton
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote).foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                            }
                            if let reply {
                                AIReplyCard(text: reply)
                            }
                            if let clarifyPrompt { clarifySection(clarifyPrompt) }
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
            .animation(.easeInOut(duration: 0.45), value: isLoading)   // 글로우 페이드 인/아웃
            .navigationTitle("")
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
        // TextEditor(무거운 UITextView) 대신 TextField(axis:.vertical) — 첫 타이핑 렉↓, 플레이스홀더 내장.
        TextField(lang.tr("예: 매주 월요일 7시 영어학원 · 다음주 월요일 급식 · 내일 뭐 있어? · 다크모드로 바꿔줘"),
                  text: $inputText, axis: .vertical)
            .focused($editorFocused)
            .lineLimit(nil)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .padding(.trailing, 40)   // 마이크 버튼 자리
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .glassCard(cornerRadius: 20)
            .overlay(alignment: .bottomTrailing) { micButton }
    }

    /// 꾹(0.35초) 눌렀다 떼면 토글 — 빠른 탭 오작동 방지. 작동 중엔 아이콘이 빨간색으로만 바뀜.
    private var micButton: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(speech.isRecording ? .red : .secondary)
            .frame(width: 46, height: 46)
            .glassEffect(.regular.interactive(), in: Circle())
            .contentShape(Circle())
            .padding(10)
            .animation(.easeInOut(duration: 0.18), value: speech.isRecording)
            .onLongPressGesture(minimumDuration: 0.35) {   // 확실히 꾹 눌러야 토글(오작동 방지)
                editorFocused = false
                speech.toggle()
                Haptics.impact(.heavy)                      // 강한 햅틱
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
                        RoundedRectangle(cornerRadius: 3).fill(EventPalette.color(idx, of: results.count)).frame(width: 4)
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

    /// "어떤 것을 삭제할까요?" 후보 목록 — 탭하면 그 일정 삭제.
    private func clarifySection(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(prompt).font(.subheadline).bold().padding(.leading, 4)
            ForEach(clarifyCandidates) { c in
                Button { deleteCandidate(c) } label: {
                    HStack(spacing: 12) {
                        Text(c.start.formatted(.dateTime.month().day().hour().minute().locale(lang.locale)))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(c.title).font(.subheadline).bold()
                        Spacer()
                        Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                    }
                    .padding(12).glassCard(cornerRadius: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deleteCandidate(_ c: DeleteCandidate) {
        if let e = find(c.id) {
            context.delete(e)
            try? context.save()
            reply = lang.tr("삭제했어요") + ": \(c.title)"
        }
        clarifyCandidates = []
        clarifyPrompt = nil
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
        errorMessage = nil; reply = nil; results = []; clarifyCandidates = []; clarifyPrompt = nil
        let text = inputText
        isLoading = true; defer { isLoading = false }
        do {
            let result = try await AppleIntelligenceClient()
                .generateSchedule(from: text, now: .now, existing: fetchUpcoming())

            // 즉시 액션(외형/급식/일정 질문/삭제 후보) 처리 → 답변 모음
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
                case .clarifyDelete(let cands, let prompt):
                    clarifyCandidates = cands
                    clarifyPrompt = prompt
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
        d.fetchLimit = 12   // 컨텍스트(글자수) 절약 — 가까운 일정만
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

// AI 처리 중 배경에서 천천히 떠다니는 알록달록한 빛.
private struct AIThinkingGlow: View {
    @State private var t = false
    var body: some View {
        ZStack {
            blob(Color(red: 0.50, green: 0.40, blue: 1.00), 280, -90, -130, 90, 70)
            blob(Color(red: 0.95, green: 0.40, blue: 0.80), 250, 110, 150, -80, -50)
            blob(Color(red: 0.30, green: 0.72, blue: 1.00), 240, -70, 120, 130, 180)
            blob(Color(red: 0.40, green: 0.90, blue: 0.75), 220, 80, -90, -110, 40)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { t = true } }
    }
    private func blob(_ c: Color, _ size: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> some View {
        Circle().fill(c.opacity(0.45)).frame(width: size, height: size).blur(radius: 85)
            .offset(x: t ? x1 : x2, y: t ? y1 : y2)
    }
}

// Apple Intelligence 답변 — 천상의 느낌(은은한 오로라 + 위에서 내리는 빛 + 부드럽게 숨 쉬는 발광 헤일로).
private struct AIReplyCard: View {
    let text: String
    @State private var glow = false

    private let corner: CGFloat = 24

    private var headerGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.62, green: 0.58, blue: 1.0),
                                Color(red: 0.55, green: 0.80, blue: 1.0)],
                       startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(headerGradient)
                Text("AI")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .tracking(0.3)
                    .foregroundStyle(.secondary)
            }

            Text(text)
                .font(.system(.subheadline, design: .default))   // 기본 SF Pro · 약간 작게
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(.ultraThinMaterial)
                // 은은한 오로라 틴트
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(LinearGradient(colors: [
                        Color(red: 0.62, green: 0.55, blue: 0.98).opacity(0.22),
                        Color(red: 0.95, green: 0.66, blue: 0.86).opacity(0.13),
                        Color(red: 0.50, green: 0.80, blue: 0.98).opacity(0.20)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                // 천상의 빛 — 위에서 내리는 라디얼 하이라이트
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(RadialGradient(colors: [.white.opacity(0.38), .clear],
                                         center: .top, startRadius: 0, endRadius: 190))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [
                    .white.opacity(0.55),
                    Color(red: 0.70, green: 0.62, blue: 1.0).opacity(0.35),
                    .clear
                ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        // 발광 헤일로 — 천천히 숨 쉬듯(빠른 반짝임 아님)
        .shadow(color: Color(red: 0.50, green: 0.45, blue: 0.98).opacity(glow ? 0.40 : 0.22),
                radius: glow ? 26 : 18, y: 8)
        .shadow(color: Color(red: 0.55, green: 0.80, blue: 1.0).opacity(glow ? 0.24 : 0.12),
                radius: glow ? 34 : 22, y: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { glow = true }
        }
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
