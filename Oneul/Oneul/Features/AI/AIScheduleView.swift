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
    @State private var amPmPending: [ParsedEvent] = []             // 오전/오후 확인이 필요한 일정
    @State private var seriesPending: [ParsedEvent] = []           // 반복 일정 삭제 — 이번 것만/전체 확인
    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("neisOffice") private var neisOffice = ""
    @AppStorage("neisCode") private var neisCode = ""
    @AppStorage("neisName") private var neisName = ""
    @AppStorage("neisKind") private var neisKind = ""
    @State private var speech = SpeechRecognizer()
    @FocusState private var editorFocused: Bool
    @AppStorage("aiMeridiemTipShown") private var meridiemTipShown = false   // 첫 진입 팁 1회
    @State private var showMeridiemTip = false
    private let lang = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if isLoading {                                    // 처리 중일 때만 렌더(무거운 blur 4개를 idle엔 안 그림 → 진입 렉↓)
                    AIThinkingGlow().transition(.opacity)
                }
                #if os(iOS)
                GeometryReader { geo in
                    ScrollView {
                        contentStack
                            .padding(16)
                            .frame(maxWidth: 640).frame(maxWidth: .infinity)
                            .frame(minHeight: geo.size.height, alignment: .top)   // 빈 곳 어디든 탭 → 키보드 내림
                            .contentShape(Rectangle())
                            .onTapGesture { endEditingGlobally() }
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                #else
                contentStack.padding(16).frame(maxWidth: .infinity)   // 맥: 스크롤/GeometryReader 없이 콘텐츠에 딱 맞게(팝오버가 내용 높이대로)
                #endif
            }
            .animation(.easeInOut(duration: 0.45), value: isLoading)   // 글로우 페이드 인/아웃
            .navigationTitle(lang.tr("AI 일정"))
            .navBarInline()
            .task {
                AppleIntelligenceClient.prewarm()
                if !meridiemTipShown { showMeridiemTip = true; meridiemTipShown = true }   // 첫 진입 1회 팁
            }
            .alert(lang.tr("더 정확하게 쓰는 팁"), isPresented: $showMeridiemTip) {
                Button(lang.tr("확인"), role: .cancel) {}
            } message: {
                Text(lang.tr("시간 앞에 '오전/오후'를 함께 적으면 훨씬 정확해요.\n예) 내일 오전 8시 수학 · 금요일 오후 5시 학원"))
            }
            .onChange(of: speech.transcript) { _, t in if !t.isEmpty { inputText = t } }
            .onDisappear { speech.stop() }
            #if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(lang.tr("완료")) { editorFocused = false }
                }
            }
            #endif
            .sheet(isPresented: Binding(get: { editingIndex != nil }, set: { if !$0 { editingIndex = nil } })) {
                if let i = editingIndex, results.indices.contains(i) {
                    AIResultEditView(event: $results[i])
                    #if os(iOS)
                        .presentationDetents([.medium, .large])
                    #else
                        .frame(minWidth: 480, minHeight: 600)
                    #endif
                }
            }
        }
    }

    @ViewBuilder private var contentStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            inputCard
            generateButton
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal, 4)
            }
            if let reply { AIReplyCard(text: reply) }
            if let clarifyPrompt { clarifySection(clarifyPrompt) }
            if !amPmPending.isEmpty { amPmSection }
            if !seriesPending.isEmpty { seriesSection }
            if !results.isEmpty { resultsSection }
        }
    }

    private var inputCard: some View {
        // TextEditor(무거운 UITextView) 대신 TextField(axis:.vertical) — 첫 타이핑 렉↓, 플레이스홀더 내장.
        TextField(lang.tr("예: 매주 월요일 7시 영어학원 · 다음주 월요일 급식 · 내일 뭐 있어? · 다크모드로 바꿔줘"),
                  text: $inputText, axis: .vertical)
            .textFieldStyle(.plain)          // 맥 기본 파란 포커스 링 제거 → 평범한 입력
            .focused($editorFocused)
            .lineLimit(nil)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .padding(.trailing, 40)   // 마이크 버튼 자리
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .glassCard(cornerRadius: 22)
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
            .onTapGesture {                                 // 탭 = 토글(롱프레스 전용은 고장으로 오인됨) — 재탭으로 즉시 취소
                editorFocused = false
                speech.onDenied = { errorMessage = lang.tr("마이크·음성 인식 권한이 꺼져 있어요. 시스템 설정에서 허용해 주세요.") }
                speech.toggle()
                Haptics.impact(.medium)
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
                                        .background(Color.appAccent, in: Capsule())
                                }
                            }
                            if e.action == .delete && e.targetID == nil {
                                Text(String(format: lang.tr("제목이 같은 일정 %d개 삭제"), bulkDeleteCount(e.title)))
                                    .font(.caption2).foregroundStyle(.red)
                            } else {
                                Text("\(timeText(e.start)) – \(timeText(e.end))" +
                                     (e.location.isEmpty ? "" : " · \(e.location)"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if e.inferredPM {   // 확률 기반 기본값 적용 → 해석 근거 표시(즉시 정정 가능)
                                Text(String(format: lang.tr("오후 %d시로 해석했어요 — 아니면 눌러서 고쳐 주세요"), hour12(e.start)))
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                            if e.deleteSeries {   // 반복 전체 삭제 예고
                                Text(lang.tr("이후 일정 모두 삭제")).font(.caption2).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if e.action != .delete {
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 22)
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

    private func hour12(_ date: Date) -> Int {
        let h = Calendar.current.component(.hour, from: date) % 12
        return h == 0 ? 12 : h
    }

    /// 오전/오후를 확신 못 한 일정 — 사용자가 한 번 탭해 확정(한 번에 질문 1개 원칙, 카드당 선택지 2개).
    private var amPmSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(amPmPending) { e in
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(format: lang.tr("'%@' — 오전 %d시인가요, 오후 %d시인가요?"),
                                e.title, hour12(e.start), hour12(e.start)))
                        .font(.subheadline).bold()
                    HStack(spacing: 8) {
                        Button(String(format: lang.tr("오전 %d시"), hour12(e.start))) { resolveAmPm(e, pm: false) }
                        Button(String(format: lang.tr("오후 %d시"), hour12(e.start))) { resolveAmPm(e, pm: true) }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).glassCard(cornerRadius: 22)
            }
        }
    }

    private func resolveAmPm(_ e: ParsedEvent, pm: Bool) {
        guard let idx = amPmPending.firstIndex(where: { $0.id == e.id }) else { return }
        var ev = amPmPending.remove(at: idx)
        let cal = Calendar.current
        let h12 = cal.component(.hour, from: ev.start) % 12
        let newH = pm ? (h12 == 0 ? 12 : h12 + 12) : h12
        let dur = max(ev.end.timeIntervalSince(ev.start), 3600)
        if let s = cal.date(bySettingHour: newH, minute: cal.component(.minute, from: ev.start),
                            second: 0, of: ev.start) {
            ev.start = s; ev.end = s.addingTimeInterval(dur)
        }
        ev.amPmAmbiguous = false
        results.append(ev)
        results.sort { $0.start < $1.start }
        Haptics.impact(.light)
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
                    .padding(12).glassCard(cornerRadius: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func deleteCandidate(_ c: DeleteCandidate) {
        AIDeleteContext.lastChosen = c.id   // "아니 그거 말고" 후속용
        if let e = find(c.id) {
            if e.isRecurring {
                // 반복 일정 — 바로 지우지 않고 이번 것만/전체 확인
                seriesPending.append(ParsedEvent(title: e.title, start: e.start, end: e.end,
                                                 location: e.location, action: .delete, targetID: e.id))
            } else {
                context.delete(e)
                try? context.save()
                reply = lang.tr("삭제했어요") + ": \(c.title)"
            }
        }
        clarifyCandidates = []
        clarifyPrompt = nil
    }

    /// 기간 내 사용자 일정(source="")을 삭제 미리보기 목록으로 펼친다. 시간표·학사일정은 건드리지 않는다.
    private func rangeDeleteEvents(from: Date, to: Date) -> [ParsedEvent] {
        var d = FetchDescriptor<ScheduleEvent>(
            predicate: #Predicate { $0.start >= from && $0.start < to && $0.source == "" },
            sortBy: [SortDescriptor(\.start)])
        d.fetchLimit = 300
        let items = (try? context.fetch(d)) ?? []
        return items.map { ParsedEvent(title: $0.title, start: $0.start, end: $0.end,
                                       location: $0.location, action: .delete, targetID: $0.id) }
    }

    /// 반복 일정 삭제 확인 — 이번 것만 vs 이후 반복 모두. 선택 즉시 실행.
    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(seriesPending) { e in
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(format: lang.tr("'%@'은(는) 반복 일정이에요. 어떻게 삭제할까요?"), e.title))
                        .font(.subheadline).bold()
                    Text(e.start.formatted(.dateTime.month().day().weekday(.short).hour().minute().locale(lang.locale)))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(lang.tr("이 일정만 삭제")) { applySeriesChoice(e, wholeSeries: false) }
                        Button(role: .destructive) { applySeriesChoice(e, wholeSeries: true) } label: {
                            Text(lang.tr("이후 일정 모두 삭제"))
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).glassCard(cornerRadius: 22)
            }
        }
    }

    private func applySeriesChoice(_ e: ParsedEvent, wholeSeries: Bool) {
        seriesPending.removeAll { $0.id == e.id }
        guard let t = find(e.targetID) else { return }
        if wholeSeries { EventActions.deleteFutureSeries(from: t, in: context) }
        else { EventActions.deleteSingle(t, in: context) }
        reply = lang.tr("삭제했어요") + ": \(e.title)"
        Haptics.notify(.warning)
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
        amPmPending = []; seriesPending = []
        let text = FastScheduleParser.normalizeKoreanTime(inputText)   // "한시"→"1시" — 음성 한글 수사 보정
        isLoading = true; defer { isLoading = false }
        do {
            let result = try await AppleIntelligenceClient()
                .generateSchedule(from: text, now: .now, existing: fetchUpcoming(), context: buildParseContext())

            // 즉시 액션(외형/급식/일정 질문/삭제 후보) 처리 → 답변 모음
            var replies: [String] = []
            var rangeEvents: [ParsedEvent] = []
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
                case .deleteRange(let from, let to):
                    // 기간 범위 삭제 — 사용자 일정만 목록으로 펼쳐 미리보기(적용하기를 눌러야 실제 삭제)
                    let evs = rangeDeleteEvents(from: from, to: to)
                    if evs.isEmpty {
                        replies.append(lang.tr("그 기간에 삭제할 일정이 없어요."))
                    } else {
                        rangeEvents = evs
                        replies.append(String(format: lang.tr("일정 %d개를 찾았어요 — 적용하기를 누르면 삭제돼요."), evs.count))
                    }
                case .unknown:
                    break
                }
            }

            // 반복 시리즈 삭제: 대상이 반복 일정이면 — '전부/반복' 단서가 있으면 이후 전체 삭제로,
            // 없으면 이번 것만/전체를 물어봄(파괴적 작업은 보수적으로)
            var evs = result.events
            let wantsSeries = ["전부", "모두", "싹", "몽땅", "반복", "시리즈", "전체"].contains { text.contains($0) }
            var ask: [ParsedEvent] = []
            for i in evs.indices where evs[i].action == .delete && evs[i].targetID != nil {
                guard let t = find(evs[i].targetID), t.isRecurring else { continue }
                if wantsSeries { evs[i].deleteSeries = true } else { ask.append(evs[i]) }
            }
            let askIDs = Set(ask.map(\.id))
            evs.removeAll { askIDs.contains($0.id) }
            seriesPending = ask

            // 오전/오후를 확신 못 한 일정은 결과에 넣지 않고 먼저 물어봄(선택하면 결과로 이동)
            amPmPending = evs.filter { $0.amPmAmbiguous }.sorted { $0.start < $1.start }
            results = (evs.filter { !$0.amPmAmbiguous } + rangeEvents).sorted { $0.start < $1.start }
            if !replies.isEmpty { reply = replies.joined(separator: "\n\n") }

            if result.isEmpty {
                errorMessage = lang.tr("무엇을 할지 이해하지 못했어요. 다시 말해 주세요.")
            } else {
                inputText = ""   // 처리됨(미리보기는 results로, 답변은 reply로)
            }
        } catch is AIContentBlocked {
            // 자극적/민감 표현으로 모델이 막은 경우 — 빨간 에러 대신 순화 안내 답변
            reply = lang.tr("그 표현은 도와드리기 어려워요. 일정 내용을 부드럽게 바꿔서 다시 말해 주세요.")
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

    /// 맨숫자 시각(오전/오후 미표기) 해석용 맥락 — 방학 여부(학사일정) + 제목별 기존 등록 시각 패턴.
    private func buildParseContext() -> AIParseContext {
        var ctx = AIParseContext()
        // 방학 여부: 나이스 학사일정에서 오늘 이전 마지막 '방학/개학' 이벤트로 판정. 데이터 없으면 nil(모름).
        let now = Date()
        let academic = FetchDescriptor<ScheduleEvent>(predicate: #Predicate { $0.source == "academic" })
        if let items = try? context.fetch(academic), !items.isEmpty {
            let markers = items.filter { $0.start <= now && ($0.title.contains("방학") || $0.title.contains("개학")) }
                .sorted { $0.start < $1.start }
            if let last = markers.last { ctx.vacation = last.title.contains("방학") }
        }
        // 학습된 패턴: 최근 60일~미래 일정의 제목별 시작 시(같은 과목은 같은 시간대일 가능성이 높음)
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: now) ?? now
        var d = FetchDescriptor<ScheduleEvent>(predicate: #Predicate { $0.start >= cutoff },
                                               sortBy: [SortDescriptor(\.start, order: .reverse)])
        d.fetchLimit = 500
        for e in (try? context.fetch(d)) ?? [] {
            ctx.learnedHours[e.title, default: []].insert(Calendar.current.component(.hour, from: e.start))
        }
        return ctx
    }

    /// 수정/삭제 대상이 될 다가오는 일정(최대 25개).
    private func fetchUpcoming() -> [ExistingEvent] {
        let start = Calendar.current.startOfDay(for: Date())   // 오늘 0시부터 → 오늘 이미 지난 일정도 삭제/수정 대상
        var d = FetchDescriptor<ScheduleEvent>(
            predicate: #Predicate { $0.start >= start }, sortBy: [SortDescriptor(\.start)])
        d.fetchLimit = 15   // 컨텍스트 절약 vs 삭제 커버리지 균형
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
                    if let t = find(id) {
                        if e.deleteSeries { EventActions.deleteFutureSeries(from: t, in: context) }
                        else { context.delete(t) }
                        applied += 1
                    }
                } else {
                    // bulk: 정확히 같은 제목 우선, 없을 때만 부분 일치("수학"이 "수학여행"을 지우는 오폭 방지)
                    for t in bulkDeleteTargets(e.title) { context.delete(t); applied += 1 }
                }
            }
        }
        do {
            try context.save()
            if applied == 0 { errorMessage = lang.tr("적용할 대상을 찾지 못했어요.") }
            else { results = []; amPmPending = []; inputText = ""; errorMessage = nil }
        } catch {
            errorMessage = "저장 오류: \(error.localizedDescription)"
        }
    }

    /// 대량 삭제 대상 — 정확 일치 우선, 없으면 부분 일치.
    private func bulkDeleteTargets(_ title: String) -> [ScheduleEvent] {
        guard !title.isEmpty else { return [] }
        let all = (try? context.fetch(FetchDescriptor<ScheduleEvent>())) ?? []
        let exact = all.filter { $0.title == title }
        return exact.isEmpty ? all.filter { $0.title.contains(title) } : exact
    }
    private func bulkDeleteCount(_ title: String) -> Int { bulkDeleteTargets(title).count }

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
            .navBarInline()
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
        .glassCard(cornerRadius: 22)
    }
}
