import SwiftUI
import SwiftData

struct SchoolSetupView: View {
    @Environment(\.modelContext) private var context

    @AppStorage("neisOffice") private var office = ""
    @AppStorage("neisCode") private var code = ""
    @AppStorage("neisName") private var schoolName = ""
    @AppStorage("neisKind") private var kind = ""
    @AppStorage("neisGrade") private var grade = 1
    @AppStorage("neisClass") private var classNm = "1"

    @State private var query = ""
    @State private var results: [School] = []
    @State private var searching = false
    @State private var importing = false
    @State private var message = ""
    @State private var showPeriods = false
    @State private var periodsTick = 0
    @State private var availableClasses: [String] = []
    @FocusState private var focused: Bool
    private let lang = AppLanguage.shared

    private var gradeRange: ClosedRange<Int> { kind.contains("초") ? 1...6 : 1...3 }
    private var classOptions: [String] { availableClasses.isEmpty ? (1...20).map(String.init) : availableClasses }

    private var selected: School? {
        code.isEmpty ? nil : School(office: office, code: code, name: schoolName, kind: kind, address: "")
    }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchCard
                    if !results.isEmpty { resultsCard }
                    if let s = selected { selectedCard(s) }
                    if !message.isEmpty {
                        Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(lang.tr("학교 설정"))
        .navBarInline()
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button(lang.tr("완료")) { focused = false }
            }
        }
        #endif
    }

    // MARK: 검색
    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lang.tr("학교 검색")).font(.caption).bold().foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField(lang.tr("학교 이름 (예: 서울고등학교)"), text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .glassCard(cornerRadius: 14)
                Button(lang.tr("검색")) { Task { await search() } }
                    .buttonStyle(AccentButtonStyle())
                    .frame(maxWidth: 80)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || searching)
            }
            if searching { ProgressView().padding(.leading, 4) }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

    private var resultsCard: some View {
        LazyVStack(alignment: .leading, spacing: 8) {   // 보이는 행만 렌더(50개 비-lazy 렌더로 인한 타이핑/검색 렉 제거)
            Text(lang.tr("검색 결과")).font(.caption).bold().foregroundStyle(.secondary)
            ForEach(results) { s in
                Button { pick(s) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(s.name).font(.subheadline).bold().foregroundStyle(.primary)
                            Text(s.kind).font(.caption2).foregroundStyle(.secondary)
                        }
                        if !s.address.isEmpty {
                            Text(s.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

    // MARK: 선택 후
    private func selectedCard(_ s: School) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s.name).font(.subheadline).bold()
                Text(s.kind).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(lang.tr("변경")) { code = ""; office = ""; schoolName = ""; kind = "" }
                    .font(.caption).tint(Color.appAccentText)
            }
            Divider()
            HStack {
                Text(lang.tr("학년")).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $grade) {
                    ForEach(gradeRange, id: \.self) { Text(lang.isEnglish ? "Grade \($0)" : "\($0)학년").tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).tint(Color.appAccentText)
            }
            HStack {
                Text(lang.tr("반")).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $classNm) {
                    ForEach(classOptions, id: \.self) { Text(lang.isEnglish ? "Class \($0)" : "\($0)반").tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).tint(Color.appAccentText)
            }
            .task(id: "\(code)-\(grade)") { await loadClasses() }

            Button { withAnimation(.snappy(duration: 0.2)) { showPeriods.toggle() } } label: {
                HStack {
                    Text(lang.tr("교시 시간 조정")).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: showPeriods ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if showPeriods {
                VStack(spacing: 7) {
                    ForEach(1...PeriodSchedule.count, id: \.self) { p in
                        HStack(spacing: 6) {
                            Text(lang.isEnglish ? "P\(p)" : "\(p)교시").font(.caption).foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .leading)
                            Spacer()
                            DatePicker("", selection: timeBinding(p, true), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("~").font(.caption).foregroundStyle(.secondary)
                            DatePicker("", selection: timeBinding(p, false), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }
                .id(periodsTick)
                .padding(.top, 2)
            }

            NavigationLink {
                ElectiveSetupView(school: s, grade: grade, classNm: classNm)
            } label: {
                Text(lang.tr("시간표 가져오기"))
                    .font(.headline).foregroundStyle(Color.appOnAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
    }

    private func timeBinding(_ p: Int, _ isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                let mins = isStart ? PeriodSchedule.startMinutes(p) : PeriodSchedule.endMinutes(p)
                return Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                if isStart { PeriodSchedule.setStart(p, mins) } else { PeriodSchedule.setEnd(p, mins) }
                periodsTick += 1
            }
        )
    }

    // MARK: 동작
    private func search() async {
        focused = false
        message = ""
        results = []
        searching = true
        defer { searching = false }
        do {
            results = try await NEISClient.shared.searchSchools(query.trimmingCharacters(in: .whitespaces))
            if results.isEmpty { message = lang.tr("검색 결과가 없어요") }
        } catch {
            message = error.localizedDescription
        }
    }

    private func pick(_ s: School) {
        office = s.office; code = s.code; schoolName = s.name; kind = s.kind
        if grade > (s.kind.contains("초") ? 6 : 3) { grade = 1 }   // 학교에 맞게 학년 보정
        results = []
        message = ""
    }

    private func loadClasses() async {
        guard !code.isEmpty else { availableClasses = []; return }
        let s = School(office: office, code: code, name: schoolName, kind: kind, address: "")
        let list = (try? await NEISClient.shared.fetchClasses(school: s, grade: grade)) ?? []
        availableClasses = list
        if !list.isEmpty, !list.contains(classNm) { classNm = list.first ?? classNm }
    }

    private func importTimetable(_ s: School) async {
        message = ""
        importing = true
        defer { importing = false }
        do {
            let r = try await TimetableImporter.importAll(
                school: s, grade: grade, classNm: classNm, into: context)
            message = (r.timetable + r.academic) > 0
                ? "수업 \(r.timetable)개 · 학사일정 \(r.academic)개를 추가했어요."
                : "시간표/학사일정을 찾지 못했어요."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - 급식 카드

struct MealCard: View {
    let day: Date

    @AppStorage("neisOffice") private var office = ""
    @AppStorage("neisCode") private var code = ""
    @AppStorage("neisName") private var name = ""
    @AppStorage("neisKind") private var kind = ""

    @State private var meals: [Meal] = []
    @State private var loading = false
    @State private var failed = false          // 네트워크 실패(데이터 없음과 구분)

    private var school: School? {
        code.isEmpty ? nil : School(office: office, code: code, name: name, kind: kind, address: "")
    }
    private var dayKey: Int {   // task(id:)용 — DateFormatter 생성(느림) 없이 하루 단위 키
        Int(Calendar.current.startOfDay(for: day).timeIntervalSinceReferenceDate)
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 50)
            } else if meals.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: failed ? "wifi.exclamationmark"
                          : (Calendar.current.isDateInWeekend(day) ? "figure.walk" : "tray"))
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text(AppLanguage.shared.tr(failed ? "급식을 불러오지 못했어요"
                         : (Calendar.current.isDateInWeekend(day) ? "주말에는 급식이 없어요" : "급식 정보가 없어요")))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if failed {
                        Button(AppLanguage.shared.tr("다시 시도")) { Task { await load() } }
                            .font(.subheadline.bold()).buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity).padding(.top, 50)
            } else {
                VStack(spacing: 14) {
                    ForEach(meals) { mealBlock($0) }
                }
            }
        }
        .task(id: dayKey) { await load() }
    }

    private func mealBlock(_ m: Meal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(m.type, systemImage: icon(m.type))
                    .font(.headline).foregroundStyle(Color.appAccentText)
                Spacer()
                if !m.calorie.isEmpty {
                    Text(m.calorie).font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(menuItems(m.menu).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle().fill(Color.appAccent).frame(width: 5, height: 5)
                        Text(item.name).font(.subheadline)
                        if !item.allergy.isEmpty {   // 알레르기 번호(1 난류, 2 우유…) — 폐기하던 정보 복원
                            Text(item.allergy).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 22)
    }

    /// "*" 접두사 정리, 알레르기 번호 "(5.6)"는 분리해서 반환.
    private func menuItems(_ menu: String) -> [(name: String, allergy: String)] {
        menu.split(separator: "\n").map { line -> (String, String) in
            var s = line.trimmingCharacters(in: .whitespaces)
            while s.hasPrefix("*") { s.removeFirst() }
            var allergy = ""
            if let r = s.range(of: #"\s*\(([0-9.\s]+)\)\s*$"#, options: .regularExpression) {
                allergy = String(s[r]).trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                s.removeSubrange(r)
            }
            return (s.trimmingCharacters(in: .whitespaces), allergy)
        }.filter { !$0.0.isEmpty }
    }
    private func icon(_ type: String) -> String {
        if type.contains("조") { return "sunrise.fill" }
        if type.contains("중") { return "sun.max.fill" }
        return "moon.stars.fill"
    }

    private func load() async {
        guard let s = school else { return }
        loading = true
        defer { loading = false }
        if let r = try? await NEISClient.shared.fetchMeal(school: s, date: day) {
            meals = r; failed = false
        } else {
            meals = []; failed = true
        }
    }
}

// MARK: - 급식 탭 (날짜 슬라이드)

struct MealView: View {
    @AppStorage("neisCode") private var code = ""
    @State private var mealDay = Date()
    @State private var showSchoolSetup = false
    @Environment(\.scenePhase) private var scenePhase
    private let lang = AppLanguage.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if code.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.secondary)
                        Text(lang.tr("설정 → 학생 → 학교 설정에서\n학교를 먼저 등록하세요"))
                            .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
                        Button { showSchoolSetup = true } label: {   // 빈 상태 CTA
                            Label(lang.tr("학교 설정하기"), systemImage: "graduationcap")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(40)
                } else {
                    VStack(spacing: 10) {
                        Text(mealDay, format: .dateTime.month().day().weekday(.wide).locale(lang.locale))
                            .font(.title3).bold()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                        #if os(iOS)
                        DayPager(selectedDay: $mealDay) { day in    // 페이저 재사용 → 121개 카드 대신 3개만(렉↓)
                            ScrollView { MealCard(day: day).padding(16) }
                        }
                        #else
                        HStack(spacing: 12) {   // macOS: ‹ 오늘 › + 좌/우 화살표로 날짜 이동
                            Button { mealDay = Calendar.current.date(byAdding: .day, value: -1, to: mealDay) ?? mealDay } label: { Image(systemName: "chevron.left") }
                                .keyboardShortcut(.leftArrow, modifiers: [])
                            Spacer()
                            Button(lang.tr("오늘")) { mealDay = .now }.font(.subheadline).bold()
                            Spacer()
                            Button { mealDay = Calendar.current.date(byAdding: .day, value: 1, to: mealDay) ?? mealDay } label: { Image(systemName: "chevron.right") }
                                .keyboardShortcut(.rightArrow, modifiers: [])
                        }
                        .buttonStyle(.borderless).padding(.horizontal, 16)
                        ScrollView { MealCard(day: mealDay).padding(16) }
                            .gesture(DragGesture(minimumDistance: 40).onEnded { v in   // 좌우 슬라이드로 날짜 이동
                                guard abs(v.translation.width) > 40 else { return }
                                let n = v.translation.width > 0 ? -1 : 1
                                mealDay = Calendar.current.date(byAdding: .day, value: n, to: mealDay) ?? mealDay
                            })
                        #endif
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(lang.tr("급식"))
            .sheet(isPresented: $showSchoolSetup) { SchoolSetupView() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, mealDay < Calendar.current.startOfDay(for: Date()) {
                    mealDay = Date()   // 지난 날짜를 보던 중이면 오늘로(미래 조회는 유지)
                }
            }
        }
    }

}
