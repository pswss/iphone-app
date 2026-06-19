import SwiftUI
import SwiftData

struct EventEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let event: ScheduleEvent?
    let day: Date

    @State private var title = ""
    @State private var location = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var reminderMinutes = 10
    @State private var reminderMinutes2 = -1
    @State private var recurrence: Recurrence = .none
    @State private var weekdays: Set<Int> = []
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var showDeleteOptions = false
    @State private var showPlaceSheet = false
    @FocusState private var focusedField: Field?
    private let lang = AppLanguage.shared

    private enum Field { case title }
    private var isEditing: Bool { event != nil }

    private let reminderOptions: [(label: String, value: Int)] = [
        ("없음", -1), ("정시", 0), ("5분 전", 5), ("10분 전", 10), ("30분 전", 30), ("1시간 전", 60)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        field(lang.tr("제목")) {
                            TextField(lang.tr("제목"), text: $title)
                                .focused($focusedField, equals: .title)
                                .multilineTextAlignment(.trailing)
                        }
                        field(lang.tr("장소")) {
                            Button { showPlaceSheet = true } label: {
                                Text(location.isEmpty ? lang.tr("위치") : location)
                                    .foregroundStyle(location.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                        field(lang.tr("시작")) {
                            DatePicker("", selection: $start).labelsHidden()
                        }
                        field(lang.tr("종료")) {
                            DatePicker("", selection: $end, in: start...).labelsHidden()
                        }
                        field(lang.tr("알림")) {
                            reminderPicker($reminderMinutes)
                        }
                        if reminderMinutes != -1 {
                            field(lang.tr("2차 알림")) {
                                reminderPicker($reminderMinutes2)
                            }
                        }
                        if !isEditing {
                            field(lang.tr("반복")) {
                                Picker("", selection: $recurrence) {
                                    ForEach(Recurrence.allCases) { Text(lang.tr($0.label)).tag($0) }
                                }
                                .labelsHidden().tint(Color.appAccentText)
                            }
                            if recurrence == .weekly { weekdaySelector }
                            if recurrence != .none {
                                field(lang.tr("반복 종료일")) {
                                    Toggle("", isOn: $hasEndDate).labelsHidden().tint(Color.appAccent)
                                }
                                if hasEndDate {
                                    field(lang.tr("종료일")) {
                                        DatePicker("", selection: $endDate, in: start...,
                                                   displayedComponents: .date).labelsHidden()
                                    }
                                }
                            }
                        }

                        if isEditing { deleteSection }
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                    .onTapGesture { UIApplication.shared.endEditing() }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? lang.tr("일정 편집") : lang.tr("새 일정"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.tr("취소")) { dismiss() }.tint(Color.appAccentText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? lang.tr("저장") : lang.tr("추가"), action: save)
                        .bold().tint(Color.appAccentText)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button(lang.tr("완료")) { focusedField = nil }
                }
            }
            .sheet(isPresented: $showPlaceSheet) { PlaceSearchSheet(location: $location) }
            .onAppear(perform: load)
        }
    }

    private func reminderPicker(_ binding: Binding<Int>) -> some View {
        Picker("", selection: binding) {
            ForEach(reminderOptions, id: \.value) { Text(lang.tr($0.label)).tag($0.value) }
        }
        .labelsHidden().tint(Color.appAccentText)
    }

    // MARK: 삭제 (옵션이 삭제 버튼 바로 위에 인라인으로)
    private var deleteSection: some View {
        VStack(spacing: 8) {
            if showDeleteOptions {
                ForEach(deleteChoices, id: \.label) { choice in
                    Button(role: .destructive) { choice.action() } label: {
                        Text(choice.label).font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .tint(.red).glassCard(cornerRadius: 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            Button(role: .destructive) {
                withAnimation(.snappy(duration: 0.22)) { showDeleteOptions.toggle() }
            } label: {
                Label(showDeleteOptions ? lang.tr("취소") : lang.tr("일정 삭제"),
                      systemImage: showDeleteOptions ? "xmark" : "trash")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .tint(showDeleteOptions ? .secondary : .red)
            .glassCard(cornerRadius: 18)
        }
        .padding(.top, 8)
    }

    private var deleteChoices: [(label: String, action: () -> Void)] {
        guard let event else { return [] }
        if event.isRecurring {
            return [
                (lang.tr("이 일정만 삭제"), { EventActions.deleteSingle(event, in: context); dismiss() }),
                (lang.tr("이후 일정 모두 삭제"), { EventActions.deleteFutureSeries(from: event, in: context); dismiss() })
            ]
        }
        return [(lang.tr("삭제"), { EventActions.deleteSingle(event, in: context); dismiss() })]
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassCard(cornerRadius: 18)
    }

    private var weekdaySelector: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { wd in
                let on = weekdays.contains(wd)
                Button {
                    if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                } label: {
                    Text(weekdaySymbol(wd))
                        .font(.subheadline).bold()
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? Color.appAccent : Color.clear, in: Circle())
                        .foregroundStyle(on ? Color.appOnAccent : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .glassCard(cornerRadius: 18)
    }

    private func weekdaySymbol(_ wd: Int) -> String {
        let ko = ["일", "월", "화", "수", "목", "금", "토"]
        let en = ["S", "M", "T", "W", "T", "F", "S"]
        return (lang.isEnglish ? en : ko)[wd - 1]
    }

    private func load() {
        if let event {
            title = event.title
            location = event.location
            start = event.start
            end = event.end
            reminderMinutes = event.reminderMinutes
            reminderMinutes2 = event.reminderMinutes2
        } else {
            let cal = Calendar.current
            let base = cal.isDateInToday(day) ? Date() : day
            let hour = cal.date(bySettingHour: min(23, cal.component(.hour, from: base) + (cal.isDateInToday(day) ? 1 : 9)),
                                minute: 0, second: 0, of: base) ?? base
            start = hour
            end = hour.addingTimeInterval(60 * 60)
            weekdays = [cal.component(.weekday, from: hour)]
            endDate = cal.date(byAdding: .month, value: 3, to: hour) ?? hour
        }
    }

    private func save() {
        if let event {
            event.title = title; event.location = location
            event.start = start; event.end = end
            event.reminderMinutes = reminderMinutes
            event.reminderMinutes2 = reminderMinutes != -1 ? reminderMinutes2 : -1
            try? context.save()
        } else {
            EventActions.create(title: title, start: start, end: end, location: location,
                                reminderMinutes: reminderMinutes,
                                reminderMinutes2: reminderMinutes != -1 ? reminderMinutes2 : -1,
                                recurrence: recurrence,
                                weekdays: recurrence == .weekly ? weekdays : [],
                                endDate: hasEndDate ? endDate : nil, into: context)
        }
        dismiss()
    }
}
