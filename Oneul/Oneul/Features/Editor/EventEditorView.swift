import SwiftUI
import SwiftData

struct EventEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let event: ScheduleEvent?
    let day: Date
    var prefillStart: Date? = nil

    @State private var title = ""
    @State private var location = ""
    @State private var notes = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var reminderMinutes = 10
    @State private var reminderMinutes2 = -1
    @State private var recurrence: Recurrence = .none
    @State private var weekdays: Set<Int> = []
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var showDeleteOptions = false
    @State private var showScopeOptions = false          // 반복 일정 저장 시 '이 일정만/이후 전체'
    @State private var originalWeekdays: Set<Int> = []   // 규칙 변경 감지용(변경 시 시리즈 재생성)
    @State private var originalEndDate: Date?
    @State private var showPlaceSheet = false
    @State private var pinned = false            // 주요 일정(상단 스와이프 밴드)
    @State private var loadedOnce = false        // load() 이후에만 시작-종료 연동(초기 세팅 오염 방지)
    @FocusState private var focusedField: Field?
    private let lang = AppLanguage.shared

    private enum Field { case title }
    private var isEditing: Bool { event != nil }
    private var rowAnim: Animation? { reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1.0) }

    private let reminderOptions: [(label: String, value: Int)] = [
        ("없음", -1), ("정시", 0), ("5분 전", 5), ("10분 전", 10), ("30분 전", 30), ("1시간 전", 60), ("하루 전", 1440)
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
                            HStack(spacing: 10) {
                                Button { showPlaceSheet = true } label: {
                                    Text(location.isEmpty ? lang.tr("위치") : location)
                                        .foregroundStyle(location.isEmpty ? .secondary : .primary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                if !location.isEmpty {
                                    Button { MapDirections.open(to: location) } label: {   // 네이버 지도 길찾기
                                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                            .foregroundStyle(Color.appAccentText)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        field(lang.tr("시작")) {
                            DatePicker("", selection: $start).labelsHidden()
                                .onChange(of: start) { old, new in
                                    guard loadedOnce else { return }
                                    end = end.addingTimeInterval(new.timeIntervalSince(old))   // 길이 유지(애플 캘린더식)
                                }
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

                        field(lang.tr("주요 일정")) {
                            Toggle("", isOn: $pinned).labelsHidden().tint(Color.appAccent)
                        }

                        // 메모 — 모델에 있었지만 UI가 없던 필드
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lang.tr("메모")).foregroundStyle(.secondary)
                            TextField(lang.tr("메모 (선택)"), text: $notes, axis: .vertical)
                                .lineLimit(2...5).textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .glassCard(cornerRadius: 22)

                        if isEditing { deleteSection }
                    }
                    .padding(16)
                    // 조건부 행(2차 알림·요일·반복 종료일)이 툭 튀지 않게 — 스프링으로 밀려나며 등장
                    .animation(rowAnim, value: reminderMinutes == -1)
                    .animation(rowAnim, value: recurrence)
                    .animation(rowAnim, value: hasEndDate)
                    .contentShape(Rectangle())
                    .onTapGesture { endEditingGlobally() }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isEditing ? lang.tr("일정 편집") : lang.tr("새 일정"))
            .navBarInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lang.tr("취소")) { dismiss() }.tint(Color.appAccentText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? lang.tr("저장") : lang.tr("추가"), action: save)
                        .bold().tint(Color.appAccentText)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer(); Button(lang.tr("완료")) { focusedField = nil }
                }
                #endif
            }
            .sheet(isPresented: $showPlaceSheet) { PlaceSearchSheet(location: $location) }
            .confirmationDialog(lang.tr("반복 일정 수정"), isPresented: $showScopeOptions, titleVisibility: .visible) {
                Button(lang.tr("이 일정만 수정")) { performSave(singleOnly: true) }
                Button(lang.tr("이후 일정 모두 수정")) { performSave(singleOnly: false) }
                Button(lang.tr("취소"), role: .cancel) {}
            }
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
            let choices = deleteChoices
            if choices.count <= 1 {
                // 단일 일정: 한 번에 바로 삭제
                Button(role: .destructive) { choices.first?.action() } label: {
                    Label(lang.tr("일정 삭제"), systemImage: "trash")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .tint(.red).glassCard(cornerRadius: 22)
            } else {
                // 반복 일정: 옵션(이 일정만 / 이후 모두). 취소 없이 다시 눌러 접기.
                if showDeleteOptions {
                    ForEach(choices, id: \.label) { choice in
                        Button(role: .destructive) { choice.action() } label: {
                            Text(choice.label).font(.headline)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .tint(.red).glassCard(cornerRadius: 22)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.22)) { showDeleteOptions.toggle() }
                } label: {
                    Label(lang.tr("일정 삭제"), systemImage: "trash")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .tint(.red).glassCard(cornerRadius: 22)
            }
        }
        .padding(.top, 8)
    }

    private var deleteChoices: [(label: String, action: () -> Void)] {
        guard let event else { return [] }
        if event.isRecurring {
            return [
                (lang.tr("이 일정만 삭제"), { EventActions.deleteSingle(event, in: context); Haptics.notify(.warning); dismiss() }),
                (lang.tr("이후 일정 모두 삭제"), { EventActions.deleteFutureSeries(from: event, in: context); Haptics.notify(.warning); dismiss() })
            ]
        }
        return [(lang.tr("삭제"), { EventActions.deleteSingle(event, in: context); Haptics.notify(.warning); dismiss() })]
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            content()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassCard(cornerRadius: 22)
    }

    private var weekdaySelector: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { wd in
                let on = weekdays.contains(wd)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                    }
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
        .glassCard(cornerRadius: 22)
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
            notes = event.notes
            start = event.start
            end = event.end
            reminderMinutes = event.reminderMinutes
            reminderMinutes2 = event.reminderMinutes2
            recurrence = Recurrence(rawValue: event.recurrenceRaw) ?? .none   // 반복 복원(수정에서 편집 가능)
            pinned = event.pinned
            weekdays = [Calendar.current.component(.weekday, from: event.start)]
            endDate = Calendar.current.date(byAdding: .month, value: 3, to: event.start) ?? event.start
            // 반복 시리즈면 실제 인스턴스들에서 요일·종료일을 복원 — 이 회차 요일 1개로 리셋돼
            // 저장 시 나머지 요일 회차가 통째로 사라지던 데이터 유실 방지
            if event.isRecurring {
                let sid = event.seriesID
                let d = FetchDescriptor<ScheduleEvent>(predicate: #Predicate { $0.seriesID == sid })
                if let series = try? context.fetch(d), !series.isEmpty {
                    if recurrence == .weekly {
                        weekdays = Set(series.map { Calendar.current.component(.weekday, from: $0.start) })
                    }
                    if let last = series.map(\.start).max() {
                        endDate = last
                        hasEndDate = true
                    }
                }
                originalWeekdays = weekdays
                originalEndDate = endDate
            }
        } else {
            let cal = Calendar.current
            let base = cal.isDateInToday(day) ? Date() : day
            let defaultHour = cal.date(bySettingHour: min(23, cal.component(.hour, from: base) + (cal.isDateInToday(day) ? 1 : 9)),
                                       minute: 0, second: 0, of: base) ?? base
            let hour = prefillStart ?? defaultHour
            start = hour
            end = hour.addingTimeInterval(60 * 60)
            weekdays = [cal.component(.weekday, from: hour)]
            endDate = cal.date(byAdding: .month, value: 3, to: hour) ?? hour
        }
        DispatchQueue.main.async { loadedOnce = true }   // 초기 세팅 트랜잭션 이후부터 연동
    }

    private func save() {
        // 반복 일정에서 규칙(반복 종류·요일·종료일)이 그대로면 '이 일정만 / 이후 전체' 선택 제공(애플 캘린더식)
        // 규칙 자체를 바꿨으면 선택 없이 시리즈 재생성(회차별 적용이 성립 안 함)
        if let event, event.isRecurring,
           recurrence.rawValue == event.recurrenceRaw,
           recurrence != .none,
           weekdays == originalWeekdays,
           endDate == originalEndDate {
            showScopeOptions = true
            return
        }
        performSave(singleOnly: false)
    }

    private func performSave(singleOnly: Bool) {
        if let event {
            if singleOnly {
                // 이 회차만: 필드만 갱신, 시리즈(다른 회차)는 그대로
                EventActions.claimFromSource(event)   // 시간표 일정이면 원본에 톰스톤 + 사용자 소유로(자동 갱신 원복 방지)
                event.title = title; event.location = location
                event.start = start; event.end = end
                event.reminderMinutes = reminderMinutes
                event.reminderMinutes2 = reminderMinutes != -1 ? reminderMinutes2 : -1
                event.pinned = pinned; event.notes = notes
                try? context.save()
            } else if recurrence != .none || event.isRecurring {
                // 반복 설정/변경/해제 → 이 일정(+이후 시리즈)을 지우고 새 규칙으로 재생성
                // (weekdays·endDate는 load()에서 시리즈 전체 기준으로 복원돼 있어 유실 없음)
                EventActions.deleteFutureSeries(from: event, in: context)
                EventActions.create(title: title, start: start, end: end, location: location,
                                    reminderMinutes: reminderMinutes,
                                    reminderMinutes2: reminderMinutes != -1 ? reminderMinutes2 : -1,
                                    recurrence: recurrence,
                                    weekdays: recurrence == .weekly ? weekdays : [],
                                    endDate: hasEndDate ? endDate : nil, source: event.source, pinned: pinned, into: context)
            } else {
                EventActions.claimFromSource(event)   // 시간표 일정이면 원본에 톰스톤 + 사용자 소유로
                event.title = title; event.location = location
                event.start = start; event.end = end
                event.reminderMinutes = reminderMinutes
                event.reminderMinutes2 = reminderMinutes != -1 ? reminderMinutes2 : -1
                event.pinned = pinned; event.notes = notes
                try? context.save()
            }
        } else {
            EventActions.create(title: title, start: start, end: end, location: location,
                                reminderMinutes: reminderMinutes,
                                reminderMinutes2: reminderMinutes != -1 ? reminderMinutes2 : -1,
                                recurrence: recurrence,
                                weekdays: recurrence == .weekly ? weekdays : [],
                                endDate: hasEndDate ? endDate : nil, pinned: pinned, into: context)
        }
        Haptics.notify(.success)   // 저장 확인 촉각 피드백
        dismiss()
    }
}
