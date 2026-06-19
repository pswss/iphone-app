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
    @State private var recurrence: Recurrence = .none
    @State private var weekdays: Set<Int> = []
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var showDeleteOptions = false
    @FocusState private var focusedField: Field?
    private let lang = AppLanguage.shared

    private enum Field { case title, location }
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
                            TextField(lang.tr("위치"), text: $location)
                                .focused($focusedField, equals: .location)
                                .multilineTextAlignment(.trailing)
                        }
                        field(lang.tr("시작")) {
                            DatePicker("", selection: $start).labelsHidden()
                        }
                        field(lang.tr("종료")) {
                            DatePicker("", selection: $end, in: start...).labelsHidden()
                        }
                        field(lang.tr("알림")) {
                            Picker("", selection: $reminderMinutes) {
                                ForEach(reminderOptions, id: \.value) { Text(lang.tr($0.label)).tag($0.value) }
                            }
                            .labelsHidden()
                            .tint(Color.appAccentText)
                        }
                        if !isEditing {
                            field(lang.tr("반복")) {
                                Picker("", selection: $recurrence) {
                                    ForEach(Recurrence.allCases) { Text(lang.tr($0.label)).tag($0) }
                                }
                                .labelsHidden()
                                .tint(Color.appAccentText)
                            }
                            if recurrence == .weekly {
                                weekdaySelector
                            }
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

                        if isEditing {
                            Button(role: .destructive) {
                                showDeleteOptions = true
                            } label: {
                                Label(lang.tr("일정 삭제"), systemImage: "trash")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .tint(.red)
                            .glassCard(cornerRadius: 18)
                            .padding(.top, 8)
                        }
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
            .confirmationDialog(lang.tr("일정 삭제"), isPresented: $showDeleteOptions, titleVisibility: .visible) {
                if let event {
                    if event.isRecurring {
                        Button(lang.tr("이 일정만 삭제"), role: .destructive) {
                            EventActions.deleteSingle(event, in: context); dismiss()
                        }
                        Button(lang.tr("이후 일정 모두 삭제"), role: .destructive) {
                            EventActions.deleteFutureSeries(from: event, in: context); dismiss()
                        }
                    } else {
                        Button(lang.tr("삭제"), role: .destructive) {
                            EventActions.deleteSingle(event, in: context); dismiss()
                        }
                    }
                }
                Button(lang.tr("취소"), role: .cancel) {}
            }
            .onAppear(perform: load)
        }
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

    // 요일 선택 (1=일 … 7=토)
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
            try? context.save()
        } else {
            EventActions.create(title: title, start: start, end: end, location: location,
                                reminderMinutes: reminderMinutes, recurrence: recurrence,
                                weekdays: recurrence == .weekly ? weekdays : [],
                                endDate: hasEndDate ? endDate : nil, into: context)
        }
        dismiss()
    }
}
