import SwiftUI
import SwiftData

/// 선택과목 (체크 → 자동배치 → 미리보기에서 수정 → 확정).
/// 1단계: 학년 선택과목 중 본인이 듣는 것 체크.
/// 2단계: 각 선택 교시에 자동 배치한 결과를 보여주고, 이상한 교시는 직접 고치게 함. 공통 과목은 자동.
struct ElectiveSetupView: View {
    let school: School
    let grade: Int
    let classNm: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let lang = AppLanguage.shared

    @State private var loading = true
    @State private var g = TimetableImporter.GradeTimetable()
    @State private var checked: Set<String> = []
    @State private var reviewing = false
    @State private var picks: [String: String] = [:]   // "wd-p" → 선택 교시 배정 과목
    @State private var importing = false
    @State private var message = ""

    private let noneTag = "(없음)"

    var body: some View {
        ZStack {
            AppBackground()
            if loading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(lang.tr("학년 전체 시간표 불러오는 중…")).font(.caption).foregroundStyle(.secondary)
                }
            } else if g.classTT.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text(lang.tr("이 학교·학년의 시간표가 NEIS에 없어요. 그리드에서 직접 추가해 주세요."))
                        .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(40)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if reviewing { reviewPhase } else { checkPhase }
                        if !message.isEmpty {
                            Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 640).frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(lang.tr("시간표 가져오기"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: 1단계 — 체크리스트
    @ViewBuilder private var checkPhase: some View {
        if g.electives.isEmpty {
            Text(lang.tr("선택과목이 없는 공통 시간표예요. 바로 만들 수 있어요."))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            makeButton(title: lang.tr("시간표 만들기")) { Task { await confirm() } }
        } else {
            Text(lang.tr("본인이 듣는 선택과목을 모두 체크하세요. 공통 과목은 자동으로 들어가요."))
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            checklist
            makeButton(title: lang.tr("다음")) { startReview() }
        }
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(g.electives, id: \.self) { sub in
                Button { toggle(sub) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: checked.contains(sub) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked.contains(sub) ? Color.appAccentText : Color.secondary)
                        Text(sub).foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.vertical, 11).padding(.horizontal, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if sub != g.electives.last { Divider().padding(.leading, 40) }
            }
        }
        .glassCard(cornerRadius: 22)
    }

    // MARK: 2단계 — 배치 미리보기/수정
    @ViewBuilder private var reviewPhase: some View {
        Text(lang.tr("배치된 선택과목이에요. 일정이 안 맞는 과목은 고쳐주세요."))
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        ForEach(reviewWeekdays, id: \.self) { reviewDayCard($0) }
        HStack(spacing: 10) {
            Button(lang.tr("뒤로")) { reviewing = false }
                .font(.subheadline).tint(Color.appAccentText)
            makeButton(title: importing ? lang.tr("만드는 중…") : lang.tr("시간표 만들기")) {
                Task { await confirm() }
            }
        }
    }

    private var reviewWeekdays: [Int] {
        Array(Set(g.classTT.filter { g.electiveSet.contains($0.subject) }.map { $0.weekday })).sorted()
    }

    private func reviewDayCard(_ wd: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(weekdayName(wd)).font(.subheadline).bold()
            ForEach(g.classTT.filter { $0.weekday == wd && g.electiveSet.contains($0.subject) }, id: \.period) { slot in
                let key = "\(slot.weekday)-\(slot.period)"
                HStack {
                    Text(lang.isEnglish ? "P\(slot.period)" : "\(slot.period)교시")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                    Spacer()
                    Picker("", selection: pickBinding(key)) {
                        ForEach((g.offered[key] ?? []).sorted(), id: \.self) { Text($0).tag($0) }
                        Text(noneTag).tag(noneTag)
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Color.appAccentText)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity).glassCard(cornerRadius: 22)
    }

    // MARK: 공통 UI
    private func makeButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if importing { ProgressView().tint(Color.appOnAccent) }
                Text(title)
            }
        }
        .buttonStyle(AccentButtonStyle())
        .disabled(importing)
    }

    private func pickBinding(_ key: String) -> Binding<String> {
        Binding(get: { picks[key] ?? noneTag }, set: { picks[key] = $0 })
    }
    private func toggle(_ s: String) {
        if checked.contains(s) { checked.remove(s) } else { checked.insert(s) }
        Haptics.impact(.light)
    }
    private func weekdayName(_ wd: Int) -> String {
        let ko = ["", "일", "월", "화", "수", "목", "금", "토"]
        let en = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard wd >= 1, wd <= 7 else { return "" }
        return lang.isEnglish ? en[wd] : ko[wd] + "요일"
    }

    // MARK: 동작
    private func load() async {
        g = await TimetableImporter.analyzeGrade(school: school, grade: grade, classNm: classNm)
        checked = Set(g.classTT.map { $0.subject }.filter { g.electiveSet.contains($0) })
        loading = false
    }

    /// 자동배치 결과를 picks에 채우고 미리보기로.
    private func startReview() {
        var p: [String: String] = [:]
        for slot in g.classTT where g.electiveSet.contains(slot.subject) {
            let key = "\(slot.weekday)-\(slot.period)"
            let mineHere = (g.offered[key] ?? []).intersection(checked)
            if mineHere.contains(slot.subject) { p[key] = slot.subject }
            else if let c = mineHere.first { p[key] = c }
            else { p[key] = noneTag }
        }
        picks = p
        Haptics.impact(.soft)
        reviewing = true
    }

    private func confirm() async {
        importing = true
        defer { importing = false }
        var selections: [(weekday: Int, period: Int, subject: String)] = []
        for slot in g.classTT {
            if g.electiveSet.contains(slot.subject) {
                let v = picks["\(slot.weekday)-\(slot.period)"] ?? noneTag
                if v != noneTag, !v.isEmpty { selections.append((slot.weekday, slot.period, v)) }
            } else {
                selections.append((slot.weekday, slot.period, slot.subject))
            }
        }
        do {
            let r = try await TimetableImporter.importSelections(
                school: school, grade: grade, selections: selections, into: context)
            TimetableSetup.save(grade: grade, classNm: classNm, electives: checked)
            message = String(format: lang.tr("시간표를 추가했어요 (수업 %d개). 새 학사일정·다음 학기는 자동으로 갱신돼요."), r.timetable)
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
