import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleEvent.start) private var events: [ScheduleEvent]

    @State private var selectedDay: Date = .now
    @State private var editing: ScheduleEvent?
    @State private var showingAdd = false
    private let lang = AppLanguage.shared
    @AppStorage("userType") private var userType = "general"
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var slideForward = true

    private var plan: DayPlan { DayPlan(events: events, day: selectedDay) }
    private var wide: Bool { hSize == .regular }
    private var isStudent: Bool { userType == "student" }
    private var dayKey: Date { Calendar.current.startOfDay(for: selectedDay) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AppBackground()

            if wide { wideContent } else { narrowContent }

            addButton
        }
        .sheet(isPresented: $showingAdd, onDismiss: syncLiveActivity) {
            EventEditorView(event: nil, day: selectedDay)
        }
        .sheet(item: $editing, onDismiss: syncLiveActivity) { event in
            EventEditorView(event: event, day: selectedDay)
        }
        .onAppear { seedIfRequested(); syncLiveActivity() }
        .onChange(of: events) { _, _ in syncLiveActivity() }
        .onChange(of: dayKey) { old, new in slideForward = new > old }
    }

    /// 날짜별 본문(타임라인+급식+그리드) — 날짜 바뀌면 애플 캘린더식 좌/우 슬라이드.
    private var dayBody: some View {
        VStack(spacing: 16) {
            timelineCard
            if isStudent { MealCard(day: selectedDay) }
            DayGridView(plan: plan, day: selectedDay, editing: $editing)
        }
        .id(dayKey)
        .transition(.asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity)))
    }

    // MARK: 아이폰(세로 1단)
    private var narrowContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                CalendarBar(selectedDay: $selectedDay)
                dayBody
                Color.clear.frame(height: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.28), value: dayKey)
        }
    }

    // MARK: 아이패드/넓은 화면(2단). 가로=화면 꽉 채움, 세로=위 정렬 컴팩트.
    private var wideContent: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // 가로: 전체 높이를 채워 넓고 길쭉하게
                VStack(spacing: 14) {
                    header
                    HStack(alignment: .top, spacing: 22) {
                        VStack(spacing: 16) {
                            CalendarBar(selectedDay: $selectedDay)
                            timelineCard
                            if isStudent { MealCard(day: selectedDay) }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        DayGridView(plan: plan, day: selectedDay, editing: $editing)
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
                        HStack(alignment: .top, spacing: 22) {
                            VStack(spacing: 16) {
                                CalendarBar(selectedDay: $selectedDay)
                                timelineCard
                                if isStudent { MealCard(day: selectedDay) }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            DayGridView(plan: plan, day: selectedDay, editing: $editing)
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
                if !Calendar.current.isDateInToday(selectedDay) {
                    Button { withAnimation(.snappy(duration: 0.25)) { selectedDay = .now } } label: {
                        Text(lang.tr("오늘"))
                            .font(.subheadline).bold()
                            .foregroundStyle(Color.appAccentText)
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.appAccentText.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let holiday = Holidays.name(for: selectedDay) {
                Text(holiday)
                    .font(.caption).bold()
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 4)
    }

    // MARK: 타임라인 카드
    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lang.tr("오늘 타임라인")).font(.subheadline).bold()
                Spacer()
                if let next = plan.next() {
                    Text("\(lang.tr("다음 ·")) \(next.title) \(next.start.formatted(.dateTime.hour().minute().locale(lang.locale)))")
                        .font(.caption2).bold()
                        .foregroundStyle(Color.appOnAccent)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.appAccent, in: Capsule())
                }
            }

            if plan.isEmpty {
                Text(lang.tr("일정 없음"))
                    .font(.subheadline).bold()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TimelineBar(plan: plan, height: wide ? 26 : 16)
                Text(currentLine)
                    .font(.subheadline).bold()
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 24)
    }

    private var currentLine: String {
        if let cur = plan.current() { return "\(lang.tr("현재 일정 ·")) \(cur.title)" }
        if plan.next() != nil { return lang.tr("대기 중 · 다음 일정까지") }
        return lang.tr("오늘 일정 종료")
    }

    // MARK: FAB
    private var addButton: some View {
        Button {
            showingAdd = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.appOnAccent)
                .frame(width: 56, height: 56)
                .background(Color.appAccent, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
        }
        .padding(20)
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
