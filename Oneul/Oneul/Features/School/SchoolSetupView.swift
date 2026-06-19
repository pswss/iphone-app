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
    @FocusState private var focused: Bool

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
        .navigationTitle("학교 설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer(); Button("완료") { focused = false }
            }
        }
    }

    // MARK: 검색
    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("학교 검색").font(.caption).bold().foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("학교 이름 (예: 서울고등학교)", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .glassCard(cornerRadius: 14)
                Button("검색") { Task { await search() } }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("검색 결과").font(.caption).bold().foregroundStyle(.secondary)
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
                Button("변경") { code = ""; office = ""; schoolName = ""; kind = "" }
                    .font(.caption).tint(Color.appAccentText)
            }
            Divider()
            HStack {
                Text("학년").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $grade) {
                    ForEach(1...6, id: \.self) { Text("\($0)학년").tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).tint(Color.appAccentText)
            }
            HStack {
                Text("반").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $classNm) {
                    ForEach(1...15, id: \.self) { Text("\($0)반").tag("\($0)") }
                }
                .labelsHidden().pickerStyle(.menu).tint(Color.appAccentText)
            }

            Button {
                Task { await importTimetable(s) }
            } label: {
                HStack {
                    if importing { ProgressView().tint(Color.appOnAccent) }
                    Text(importing ? "가져오는 중..." : "시간표 가져오기")
                }
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(importing)
        }
        .padding(14)
        .glassCard(cornerRadius: 22)
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
            if results.isEmpty { message = "검색 결과가 없어요." }
        } catch {
            message = error.localizedDescription
        }
    }

    private func pick(_ s: School) {
        office = s.office; code = s.code; schoolName = s.name; kind = s.kind
        results = []
        message = ""
    }

    private func importTimetable(_ s: School) async {
        message = ""
        importing = true
        defer { importing = false }
        do {
            let n = try await TimetableImporter.importThisWeek(
                school: s, grade: grade, classNm: classNm, into: context)
            message = n > 0 ? "\(n)개 수업을 졸업할 때까지 추가했어요." : "이번 주 시간표를 찾지 못했어요."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - 급식 카드 (별도 칸)

struct MealCard: View {
    let day: Date

    @AppStorage("neisOffice") private var office = ""
    @AppStorage("neisCode") private var code = ""
    @AppStorage("neisName") private var name = ""
    @AppStorage("neisKind") private var kind = ""

    @State private var meals: [Meal] = []
    @State private var loading = false

    private var school: School? {
        code.isEmpty ? nil : School(office: office, code: code, name: name, kind: kind, address: "")
    }
    private var dayKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"; return f.string(from: day)
    }

    var body: some View {
        if school != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("급식").font(.subheadline).bold()
                if loading {
                    ProgressView()
                } else if meals.isEmpty {
                    Text("급식 정보 없음").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(meals) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.type).font(.caption).bold().foregroundStyle(Color.appAccentText)
                            Text(m.menu).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard(cornerRadius: 22)
            .task(id: dayKey) { await load() }
        }
    }

    private func load() async {
        guard let s = school else { return }
        loading = true
        defer { loading = false }
        meals = (try? await NEISClient.shared.fetchMeal(school: s, date: day)) ?? []
    }
}
