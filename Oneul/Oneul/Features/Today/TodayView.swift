import SwiftUI
import SwiftData
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScheduleEvent.start) private var events: [ScheduleEvent]

    @State private var selectedDay: Date = .now
    @State private var editing: ScheduleEvent?
    @State private var showingAdd = false
    @State private var addStart: Date?
    @State private var eventsByDay: [Date: [ScheduleEvent]] = [:]
    @State private var timelineProgress: CGFloat = 0   // 0=펼침, 1=완전 접힘 (스크롤에 연속 연동)
    @State private var timelineH: CGFloat = 0          // 타임라인 카드 자연 높이
    @State private var sharedScrollHour: Int?          // 모든 날 grid가 공유하는 세로 스크롤 위치(슬라이드해도 유지)
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
        .overlay(alignment: .bottomTrailing) { if !wide { addButton } }
        .sheet(isPresented: $showingAdd, onDismiss: syncLiveActivity) {
            EventEditorView(event: nil, day: selectedDay, prefillStart: addStart)
                .presentationDetents([.medium, .large])   // 절반 높이 → 위 그리드의 미리보기 블록이 보임
        }
        .sheet(item: $editing, onDismiss: syncLiveActivity) { event in
            EventEditorView(event: event, day: selectedDay)
        }
        .onAppear { seedIfRequested(); rebuildIndex(); syncLiveActivity() }
        .onChange(of: events) { _, _ in rebuildIndex(); syncLiveActivity() }
    }

    private func grid(_ p: DayPlan, _ d: Date, onScrollDelta: ((CGFloat) -> Void)? = nil) -> some View {
        DayGridView(plan: p, day: d,
                    onEdit: { editing = $0 },
                    onAdd: { addStart = $0; showingAdd = true },
                    onScrollDelta: onScrollDelta,
                    previewStart: previewFor(d),
                    scrollHour: $sharedScrollHour)
    }

    /// 새 일정 추가 시트가 떠 있고 그 시작 시각이 이 날짜면 미리보기 블록 표시.
    private func previewFor(_ d: Date) -> Date? {
        guard showingAdd, let s = addStart,
              Calendar.current.isDate(s, inSameDayAs: d) else { return nil }
        return s
    }

    // 우하단 리퀴드 글래스 + 버튼 (새 일정)
    private var addButton: some View {
        Button {
            addStart = nil
            showingAdd = true
            Haptics.impact(.light)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.appAccentText)
                .frame(width: 58, height: 58)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .padding(.trailing, 22)
        .padding(.bottom, 22)
    }

    // MARK: 아이폰(세로) — 손가락 좌우 스와이프로 날짜 이동(애플 캘린더식)
    private var narrowContent: some View {
        VStack(spacing: 12) {
            header.padding(.horizontal, 16)
            dDayBar.padding(.horizontal, 16)
            CalendarBar(selectedDay: $selectedDay).padding(.horizontal, 16)
            collapsingTimeline.padding(.horizontal, 16)   // 페이저 밖에 고정 — 슬라이드해도 안 생겼다 사라졌다 안 함
            DayPager(selectedDay: $selectedDay) { day in   // UIPageViewController 3페이지 재사용 → 렉/튐 없음
                gridPage(day)
            }
        }
        .padding(.top, 8)
        .onPreferenceChange(TimelineHeightKey.self) { if $0 > 0 { timelineH = $0 } }
    }

    // 고정 타임라인(페이저 밖) — 선택일 기준, 보이는 그리드의 스크롤량에 따라 연속 접힘
    private var collapsingTimeline: some View {
        timelineCard(plan, live: Calendar.current.isDateInToday(selectedDay))
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in
                Color.clear.preference(key: TimelineHeightKey.self, value: g.size.height)
            })
            .offset(y: -timelineH * timelineProgress)                              // 위로 말려 올라가는 모션
            .frame(height: timelineH > 0 ? max(0, timelineH * (1 - timelineProgress)) : nil, alignment: .top)
            .clippedIf(timelineProgress > 0.001)
            .opacity(Double(max(0, 1 - timelineProgress * 1.3)))
    }

    // 페이지 = 그리드만 (타임라인은 고정)
    private func gridPage(_ d: Date) -> some View {
        let p = dayPlan(for: d)
        let active = Calendar.current.isDate(d, inSameDayAs: selectedDay)
        return grid(p, d, onScrollDelta: active ? { delta in
            guard timelineH > 0 else { return }
            timelineProgress = min(1, max(0, delta / (timelineH * 0.55)))   // 스크롤 시작하면 더 빨리 접히게
        } : nil)
        .padding(.horizontal, 16)
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

// MARK: - 날짜 페이저 (UIPageViewController) — 좌우 슬라이드로 하루씩, 3페이지만 재사용(애플 캘린더식, 렉/튐 없음)
struct DayPager<Content: View>: UIViewControllerRepresentable {
    @Binding var selectedDay: Date
    @ViewBuilder var content: (Date) -> Content

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        pvc.setViewControllers([context.coordinator.host(selectedDay)], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
        guard let cur = pvc.viewControllers?.first as? Host else { return }
        if !Calendar.current.isDate(cur.day, inSameDayAs: selectedDay) {
            let forward = selectedDay > cur.day                       // 캘린더바 등 외부 변경 → 그 방향으로 애니메이션 이동
            pvc.setViewControllers([context.coordinator.host(selectedDay)],
                                   direction: forward ? .forward : .reverse, animated: true)
        } else {
            cur.rootView = AnyView(content(cur.day))                  // 데이터/상태 변경 반영(일정 추가·이동 등)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: DayPager
        init(_ parent: DayPager) { self.parent = parent }

        func host(_ day: Date) -> Host { Host(day: day, rootView: AnyView(parent.content(day))) }

        func pageViewController(_ p: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let h = vc as? Host, let d = Calendar.current.date(byAdding: .day, value: -1, to: h.day) else { return nil }
            return host(d)
        }
        func pageViewController(_ p: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let h = vc as? Host, let d = Calendar.current.date(byAdding: .day, value: 1, to: h.day) else { return nil }
            return host(d)
        }
        func pageViewController(_ p: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let h = p.viewControllers?.first as? Host,
                  !Calendar.current.isDate(parent.selectedDay, inSameDayAs: h.day) else { return }
            parent.selectedDay = h.day                                // 슬라이드 끝나면 선택일 갱신
        }
    }

    final class Host: UIHostingController<AnyView> {
        let day: Date
        init(day: Date, rootView: AnyView) {
            self.day = day
            super.init(rootView: rootView)
            view.backgroundColor = .clear
        }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError() }
    }
}

private struct TimelineHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private extension View {
    @ViewBuilder func clippedIf(_ condition: Bool) -> some View {
        if condition { self.clipped() } else { self }
    }
}

#Preview {
    TodayView()
        .modelContainer(for: ScheduleEvent.self, inMemory: true)
}
