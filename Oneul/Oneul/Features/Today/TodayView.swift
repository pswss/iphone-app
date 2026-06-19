import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleEvent.start) private var events: [ScheduleEvent]

    @State private var selectedDay: Date = .now
    @State private var editing: ScheduleEvent?
    @State private var showingAdd = false
    @State private var addStart: Date?
    @State private var eventsByDay: [Date: [ScheduleEvent]] = [:]
    @State private var timelineHidden = false
    private let lang = AppLanguage.shared
    @AppStorage("userType") private var userType = "general"
    @Environment(\.horizontalSizeClass) private var hSize

    private var plan: DayPlan { dayPlan(for: selectedDay) }
    private var wide: Bool { hSize == .regular }
    private var isStudent: Bool { userType == "student" }

    /// 날짜별로 미리 묶어둔 인덱스에서 그 날짜 일정만 꺼내 DayPlan 생성 (전체 수천 개 필터 회피).
    private func dayPlan(for day: Date) -> DayPlan {
        DayPlan(events: eventsByDay[Calendar.current.startOfDay(for: day)] ?? [], day: day)
    }
    /// events 변경 시 한 번만 날짜별 인덱스 재구성. (멀티데이는 걸친 모든 날에 등록)
    private func rebuildIndex() {
        var dict: [Date: [ScheduleEvent]] = [:]
        let cal = Calendar.current
        for e in events {
            var d = cal.startOfDay(for: e.start)
            let last = cal.startOfDay(for: e.end)
            var guardN = 0
            while d <= last && guardN < 370 {
                dict[d, default: []].append(e)
                guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = n; guardN += 1
            }
        }
        eventsByDay = dict
    }

    var body: some View {
        ZStack {
            AppBackground()
            if wide { wideContent } else { narrowContent }
        }
        .sheet(isPresented: $showingAdd, onDismiss: syncLiveActivity) {
            EventEditorView(event: nil, day: selectedDay, prefillStart: addStart)
                .presentationDetents([.medium, .large])   // 절반 높이 → 위 그리드의 미리보기 블록이 보임
        }
        .sheet(item: $editing, onDismiss: syncLiveActivity) { event in
            EventEditorView(event: event, day: selectedDay)
        }
        .onAppear { seedIfRequested(); rebuildIndex(); syncLiveActivity() }
        .onChange(of: events) { _, _ in rebuildIndex(); syncLiveActivity() }
        .onChange(of: selectedDay) { _, _ in if timelineHidden { withAnimation(.snappy(duration: 0.28)) { timelineHidden = false } } }
    }

    private func grid(_ p: DayPlan, _ d: Date, onCollapseChange: ((Bool) -> Void)? = nil) -> some View {
        DayGridView(plan: p, day: d,
                    onEdit: { editing = $0 },
                    onAdd: { addStart = $0; showingAdd = true },
                    onCollapseChange: onCollapseChange,
                    previewStart: previewFor(d))
    }

    /// 새 일정 추가 시트가 떠 있고 그 시작 시각이 이 날짜면 미리보기 블록 표시.
    private func previewFor(_ d: Date) -> Date? {
        guard showingAdd, let s = addStart,
              Calendar.current.isDate(s, inSameDayAs: d) else { return nil }
        return s
    }

    // MARK: 아이폰(세로) — 손가락 좌우 스와이프로 날짜 이동(애플 캘린더식)
    private var narrowContent: some View {
        VStack(spacing: 12) {
            header.padding(.horizontal, 16)
            dDayBar.padding(.horizontal, 16)
            CalendarBar(selectedDay: $selectedDay).padding(.horizontal, 16)
            TabView(selection: dayOffsetBinding) {
                ForEach(-180...180, id: \.self) { off in
                    dayPage(dayFor(off)).tag(off)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .padding(.top, 8)
    }

    private func dayPage(_ d: Date) -> some View {
        let p = dayPlan(for: d)
        return VStack(spacing: 12) {
            if !timelineHidden {
                timelineCard(p, live: Calendar.current.isDateInToday(d))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            grid(p, d, onCollapseChange: { hidden in
                withAnimation(.snappy(duration: 0.28)) { timelineHidden = hidden }
            })
        }
        .padding(.horizontal, 16)
    }

    private func dayFor(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
    private var dayOffsetBinding: Binding<Int> {
        Binding(
            get: {
                Calendar.current.dateComponents([.day],
                    from: Calendar.current.startOfDay(for: Date()),
                    to: Calendar.current.startOfDay(for: selectedDay)).day ?? 0
            },
            set: { selectedDay = dayFor($0) }
        )
    }

    // MARK: 아이패드/넓은 화면(2단). 가로=화면 꽉 채움, 세로=위 정렬 컴팩트.
    private var wideContent: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // 가로: 전체 높이를 채워 넓고 길쭉하게
                VStack(spacing: 14) {
                    header
                    dDayBar
                    HStack(alignment: .top, spacing: 22) {
                        VStack(spacing: 16) {
                            CalendarBar(selectedDay: $selectedDay)
                            timelineCard(plan, live: Calendar.current.isDateInToday(selectedDay))
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        grid(plan, selectedDay)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
            } else {
                // 세로: 위 정렬 컴팩트 2단
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        dDayBar
                        HStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 16) {
                                CalendarBar(selectedDay: $selectedDay)
                                timelineCard(plan, live: Calendar.current.isDateInToday(selectedDay))
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            grid(plan, selectedDay)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
            }
        }
    }

    // MARK: 헤더
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDay, format: .dateTime.day().weekday(.wide))
                    .font(.largeTitle).bold()
                Spacer()
            }
            if let holiday = Holidays.name(for: selectedDay) {
                Text(holiday)
                    .font(.caption).bold()
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    // MARK: D-Day (다가오는 시험/수능)
    private var dDays: [(title: String, days: Int)] {
        let today = Calendar.current.startOfDay(for: Date())
        var nearest: [String: Date] = [:]
        for e in events {
            let isExam = e.examKind != .none
                || ["수능", "고사", "평가", "시험", "학력"].contains { e.title.contains($0) }
            guard isExam else { continue }
            let d = Calendar.current.startOfDay(for: e.start)
            guard d >= today else { continue }
            if let cur = nearest[e.title] { if d < cur { nearest[e.title] = d } } else { nearest[e.title] = d }
        }
        return nearest.map { (title: $0.key, days: Calendar.current.dateComponents([.day], from: today, to: $0.value).day ?? 0) }
            .sorted { $0.days < $1.days }
            .prefix(3).map { $0 }
    }

    @ViewBuilder
    private var dDayBar: some View {
        let items = dDays
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.title) { item in
                        HStack(spacing: 6) {
                            Text(item.title).font(.caption2).bold().lineLimit(1)
                            Text(item.days == 0 ? "D-DAY" : "D-\(item.days)")
                                .font(.caption2).bold().foregroundStyle(Color.appOnAccent)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(item.days <= 7 ? Color.red : Color.appAccent, in: Capsule())
                        }
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                    }
                }
            }
        }
    }

    // MARK: 타임라인 카드
    private func timelineCard(_ p: DayPlan, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lang.tr("오늘 타임라인")).font(.subheadline).bold()
                Spacer()
                if let next = p.next() {
                    Text("\(lang.tr("다음 ·")) \(next.title) \(next.start.formatted(.dateTime.hour().minute().locale(lang.locale)))")
                        .font(.caption2).bold()
                        .foregroundStyle(Color.appOnAccent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.appAccent, in: Capsule())
                }
            }

            if p.isEmpty {
                Text(lang.tr("일정 없음"))
                    .font(.subheadline).bold()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TimelineBar(plan: p, height: wide ? 26 : 16, live: live)
                Text(currentLine(p))
                    .font(.subheadline).bold()
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 24)
    }

    private func currentLine(_ p: DayPlan) -> String {
        if let cur = p.current() { return "\(lang.tr("현재 일정 ·")) \(cur.title)" }
        if p.next() != nil { return lang.tr("대기 중 · 다음 일정까지") }
        return lang.tr("오늘 일정 종료")
    }

    // MARK: 동작
    private func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData"), events.isEmpty else { return }
        let now = Date()
        let samples: [(Int, Int, String, String)] = [
            (-210, -150, "아침 준비", "집"),
            (-150,  -90, "팀 회의", "3층 회의실"),
            (-110,  -50, "점심", "성수동"),
            ( -40,   40, "프로젝트 작업", "집중 모드"),
            (  70,  140, "저녁 약속", "이태원"),
            ( 160,  220, "독서", "라운지")
        ]
        for s in samples {
            let start = now.addingTimeInterval(TimeInterval(s.0 * 60))
            let end = now.addingTimeInterval(TimeInterval(s.1 * 60))
            guard Calendar.current.isDateInToday(start) else { continue }
            context.insert(ScheduleEvent(title: s.2, start: start, end: end, location: s.3))
        }
        // 멀티데이 데모: 어제 14:00 ~ 내일 16:00 (오늘에도 떠야 정상)
        let cal = Calendar.current
        if let base = cal.date(bySettingHour: 14, minute: 0, second: 0, of: now),
           let mdStart = cal.date(byAdding: .day, value: -1, to: base),
           let endBase = cal.date(bySettingHour: 16, minute: 0, second: 0, of: now),
           let mdEnd = cal.date(byAdding: .day, value: 1, to: endBase) {
            context.insert(ScheduleEvent(title: "워크숍 (어제~내일)", start: mdStart, end: mdEnd, location: "연수원"))
        }
        try? context.save()
    }

    private func syncLiveActivity() {
        let todayPlan = DayPlan(events: events, day: .now)
        LiveActivityController.shared.refresh(plan: todayPlan, dayLabel: todayLabel())
        NotificationManager.shared.reschedule(for: events)   // 전체 일정(가까운 알림 + 시험 전날)
    }

    private func todayLabel() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 EEEE"
        return f.string(from: .now)
    }
}

#Preview {
    TodayView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
